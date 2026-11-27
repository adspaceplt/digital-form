/* ADspace Digital Portal — the Assistant (2026-11-13; the user: "ok approve,
 * all colleagues, build all phases", after the Assistant mockup).
 *
 * A colleague asks in words from Ask in the console's head (⌘ J). This
 * page holds the conversation and posts it to `portal-agent`, which asks
 * Claude with a fixed set of tools and hands back its answer. Every tool
 * Claude asks for runs here, through the colleague's own sign-in:
 *   - a read (find_clients, client_summary, list_tasks, waiting_on_me,
 *     list_reports, find_colleagues and, since 2026-11-19, every other
 *     section: money, creators, suppliers, the Dashboard's figures,
 *     documents, scripts, links, the Activity record, the message logs, the
 *     Handbook and search_portal) makes the reads the screens make, under
 *     the same policies, and answers no-access, naming what it would have
 *     read, where `may()` says so;
 *   - a change (propose_*) is drawn as a card of what will be written, from
 *     and to; nothing is written until Confirm, through the function the
 *     screen uses, and Undo stands where the screen offers one;
 *   - open_page draws a button to a record, a search result or a section,
 *     only where the colleague may open it.
 * Each confirmed change is filed in the Activity record under the colleague,
 * marked as made through the Assistant (`assistant.task`, `assistant.call`,
 * `assistant.report`, `assistant.meeting`, `assistant.campaign`,
 * `assistant.set`, `assistant.whatsapp`, `assistant.schedule`).
 * Since 2026-11-13 (the user: "approve build both") it may book a month's
 * meeting, create a campaign, publish or unpublish a set, and send a
 * WhatsApp template to a client, each only behind its card; and schedule a
 * reminder or one of those for later (`agent_schedule_add`, run as the
 * colleague every five minutes). It never deletes, and never changes
 * money, billing, access or performance: no change among its tools does.
 */
(function () {
  'use strict';
  var bridge = window.ADspaceAdmin || {};
  /* A section's helper the Assistant reads (a quotation's state, the sales
     figures, a stage's words), fetched first where this visit has not yet
     (ON DEMAND, 2026-11-22); a fetch that fails answers as before. */
  function fetched(keys) { return bridge.need ? bridge.need(keys).catch(function () {}) : Promise.resolve(); }
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
  var AI_GLYPH = window.ADspaceIcons.glyph('sparkle', 'spark ai-mark');

  /* ---- Words ---------------------------------------------------------------- */
  var SAID = {
    'ai-limit': 'The daily limit for the Assistant has been reached. It resets at 12:00 am.',
    'ai-not-set-up': 'The Assistant is not set up yet. Please contact an admin.',
    'needs-update': window.ADspaceWords.line.notYet,
    'ai-key': 'The Assistant is not available at the moment. Please contact an admin.',
    'ai-credit': 'The Assistant is not available at the moment. Please contact an admin.',
    'ai-model': 'The Assistant is not available at the moment. Please contact an admin.',
    'ai-busy': 'The Assistant is busy. Try again in a minute.',
    'ai-slow': 'The answer took too long. Try a shorter question.',
    'ai-refused': 'The Assistant cannot help with that. Ask about a client, a task or a report.',
    'too-many-steps': 'That question needed too many steps. Ask about one thing at a time.',
    'expired': 'This question has expired. Please ask it again.',
    'too-long': 'This conversation is too long. Press Clear, then ask again.',
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
  var CHANNEL = window.ADspaceWords.line.meetChannel;
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
  /* A read the colleague may not make answers what it would have read and
     the section that holds it, as the rail names it (2026-11-19, the user:
     "if no control return the answer to the team member that they have no
     control to view or manage that"); Claude says it in the portal's words. */
  function noAccess(what, section) { return { error: 'no-access', what: what || 'this', section: section || null }; }
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

  /* A task asked for by its words (2026-11-13: "the xhs account renewal task"
     found nothing, list_tasks had no words to search): My Work's own search
     (ADspaceOps.taskSearch), every task the colleague may see, open or
     finished, by title, code, description, brief, client or number. */
  function findTasks(a) {
    if (!window.ADspaceOps || !window.ADspaceOps.taskSearch) return Promise.resolve({ error: 'unavailable' });
    return Promise.all([team(), loadStages()]).then(function () {
      return window.ADspaceOps.taskSearch(function () {
        var q = db.from('ops_tasks').select(TASK_COLS + ', description').is('archived_at', null);
        return a.client_id ? q.eq('client_id', a.client_id) : q;
      }, a.query);
    }).then(rows).then(function (list) {
      var hits = list.sort(function (x, y) { return (y.task_no || 0) - (x.task_no || 0); }).slice(0, 20);
      return ownersOf(hits.map(function (x) { return x.id; })).then(function (o) {
        return { tasks: hits.map(function (x) {
          var r = taskRow(x, o);
          if (x.cancelled_at) r.cancelled = true;
          return r;
        }), searched: a.query, shown: hits.length, found: list.length };
      });
    });
  }

  var READ = {
    find_clients: function (a) {
      if (!may('clients')) return Promise.resolve(noAccess('clients', 'Clients'));
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
      if (!may('clients')) return Promise.resolve(noAccess('clients', 'Clients'));
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
      if (!may('ops')) return Promise.resolve(noAccess('tasks', 'My Work'));
      if (clean(a.query || '').length >= 2) return findTasks(a);
      if (a.whose === 'everyone' && !may('ops.all')) return Promise.resolve(noAccess("the whole team's tasks", 'My Work'));
      var mine = a.whose === 'me' ? (me() || {}).id : a.whose === 'person' ? a.person_id : null;
      if (a.whose === 'person' && !a.person_id) return Promise.resolve({ error: 'person_id required' });
      if (a.whose === 'person' && a.person_id !== (me() || {}).id && !may('ops.all')) return Promise.resolve(noAccess("the whole team's tasks", 'My Work'));
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
      if (!m) return Promise.resolve(noAccess('Waiting for you', 'Dashboard'));
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
      if (!may('reports')) return Promise.resolve(noAccess('reports', 'Reports'));
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
      if (!may('ops')) return Promise.resolve(noAccess('content months', 'My Work'));
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
      if (!may('review.sets')) return Promise.resolve(noAccess('content sets', 'Content Review'));
      return db.from('batches').select('id, title, period, published, created_at').eq('client_id', a.client_id)
        .order('created_at', { ascending: false }).limit(12).then(rows).then(function (list) {
          if (!list.length) return { sets: [] };
          return db.rpc('review_set_counts', { p_sets: list.map(function (b) { return b.id; }) }).then(function (r) {
            /* A count that failed is never read as no posts. */
            if (r.error) throw new Error(r.error.message);
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
      if (!may('campaigns.campaigns')) return Promise.resolve(noAccess('creator campaigns', 'Creators'));
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
      if (!may('clients.contacts')) return Promise.resolve(noAccess('client contacts', 'Clients'));
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
  /* ---- Every other section (2026-11-19, the user: "the assistant feature is
     still weak, some questions it doesnt answer"): money, creators and
     suppliers, the Dashboard's figures, documents, video scripts, short
     links, the Activity record, the message logs and the Handbook. Each is
     the read its own screen makes, asked behind the same `may()` key, and
     each leaves out what never goes to Claude: a contact's email or number,
     bank details, an NRIC, a salary, a code. Money reaches only a colleague
     who already reads it there. ------------------------------------------- */
  function amt(n, cur) {
    var M = window.ADspaceMoney;
    var mk = cur === 'SGD' || cur === 'SG' ? 'SG' : 'MY';
    return M && M.money2 ? M.money2(Number(n) || 0, mk) : (mk === 'SG' ? 'S$ ' : 'RM ') + (Number(n) || 0).toFixed(2);
  }
  function has(v, q) { return !q || String(v || '').toLowerCase().indexOf(String(q).toLowerCase()) > -1; }
  /* A function's own refusal: denied is the colleague's access, said as
     no-access; anything else is a read that failed. */
  function fnData(r, what, section) {
    if (r.error) throw r.error;
    var d = r.data || {};
    if (d.error === 'denied') return { refused: noAccess(what, section) };
    if (d.error) throw new Error(String(d.error));
    return { data: d };
  }
  function invoke(name, body) {
    return db.functions.invoke(name, { body: body }).then(function (r) {
      if (r && r.data && r.data.error) return r.data;
      var refused = API.fnRefusal ? API.fnRefusal(r) : Promise.resolve(r.error ? 'failed' : null);
      return refused.then(function (code) { return code ? { error: code } : (r.data || { error: 'failed' }); });
    });
  }
  function words2(k) { return String(k || '').replace(/[_-]+/g, ' ').replace(/^\w/, function (c) { return c.toUpperCase(); }); }
  var CREATOR_STATE = { confirmed: 'Confirmed', pending_visit: 'Pending visit', pending_delivery: 'Pending visit', pending_draft: 'Pending draft',
    submitted: 'Submitted', reviewing: 'Reviewing', changes: 'Changes requested', scheduled: 'Scheduled', posted: 'Posted', completed: 'Completed',
    withdrawn: 'Withdrawn', replaced: 'Withdrawn' };
  var BILL_STATE = { draft: 'Draft in Bukku', processing: 'Awaiting payment', paid: 'Paid', void: 'Voided' };
  var PLATFORM_WORD = { xhs: 'rednote', instagram: 'Instagram', tiktok: 'TikTok', facebook: 'Facebook' };
  var PLATFORM_KEY = { xhs: 'xhs', rednote: 'xhs', '小红书': 'xhs', red: 'xhs', instagram: 'instagram', ig: 'instagram',
    tiktok: 'tiktok', tt: 'tiktok', facebook: 'facebook', fb: 'facebook' };
  var DOC_FAMILY = { quote_cover: 'Quotation Cover', client: 'Client letter', hr: 'HR Letter', other: 'Other document' };
  var HB_CAT = { handbook: 'Employee Handbook', sop: 'SOPs', policy: 'Policies', template: 'Templates and forms', other: 'Other' };
  var MAIL_STATE = { queued: 'Queued', sending: 'Sending', sent: 'Sent', delivered: 'Delivered', opened: 'Opened', bounced: 'Bounced',
    complained: 'Marked as spam', failed: 'Not sent', unknown: 'Not confirmed' };
  var WA_PURPOSE = { report: 'Report', feedback: 'Feedback request', creator: 'Booking', approval: 'Approval reminder', reminder: 'Reminder',
    quotation: 'Quotation', offer: 'Letter of Offer', quote_ready: 'Quotation ready', representative: 'Representative introduction', message: 'Message' };
  function waState(x) {
    return x.state === 'queued' ? 'Queued' : x.state === 'sending' ? 'Sending' : x.state === 'failed' ? 'Failed' : x.state === 'unknown' ? 'Not confirmed'
      : x.read_at ? 'Read' : x.delivered_at ? 'Delivered' : x.failed_at ? 'Failed' : 'Sent';
  }
  function monthKey(m) { return /^\d{4}-\d{2}$/.test(String(m || '')) ? m + '-01' : today().slice(0, 7) + '-01'; }
  /* What the search found, kept on the page so open_page can open it as
     search opens it (`result`, its key). */
  var found = {};
  var foundN = 0;

  Object.assign(READ, {
    /* Money: Clients' Overdue invoices, one client's unpaid ones too. */
    overdue_invoices: function (a) {
      if (!may('clients.billing')) return Promise.resolve(noAccess('invoices', 'Clients'));
      return invoke('bukku-sync', a.client_id ? { action: 'invoices', client: a.client_id } : { action: 'invoices' }).then(function (d) {
        if (d.error === 'denied') return noAccess('invoices', 'Clients');
        if (d.error) return { error: 'could-not-read', why: d.error };
        var list = (d.rows || []).map(function (l) {
          return { client: l.client_name || 'Not linked to a client', client_id_code: l.client_code || null, company: l.company || null,
            invoice: l.number, amount_due: amt(l.amount, l.currency), balance: amt(l.balance, l.currency),
            due: l.due ? dayWord(l.due) : null, days_overdue: Number(l.days) > 0 ? Number(l.days) : 0 };
        });
        var by = {};
        (d.rows || []).forEach(function (l) { if (Number(l.days) > 0) by[l.currency || 'MYR'] = (by[l.currency || 'MYR'] || 0) + (Number(l.amount) || 0); });
        return { invoices: list.slice(0, 40), shown: Math.min(list.length, 40), found: list.length,
          overdue_total: Object.keys(by).map(function (k) { return amt(by[k], k); }), read_from: 'Bukku' };
      });
    },
    /* A client's billing: complete or what is missing, never its numbers,
       emails or address. */
    client_billing: function (a) {
      if (!may('clients.billing')) return Promise.resolve(noAccess('billing details', 'Clients'));
      return Promise.all([
        db.from('clients').select('id, name, stage, market, bill_sgd, sst_applies').eq('id', a.client_id).maybeSingle(),
        db.rpc('client_billing', { p_ids: [a.client_id] })
      ]).then(function (g) {
        if (g[0].error) throw g[0].error;
        var c = g[0].data;
        if (!c) return { error: 'not-found' };
        var b = ((g[1] && g[1].data) || []).filter(function (x) { return x.id === c.id; })[0] || {};
        var missing = (Array.isArray(b.missing) ? b.missing : Array.isArray(b.billing_missing) ? b.billing_missing : []).map(words2);
        return { client: c.name, stage: STAGE[c.stage] || c.stage, registered_company_name: b.legal_name || null,
          billed_in: c.market === 'SG' && c.bill_sgd ? 'S$' : 'RM', sst_applies: c.sst_applies !== false,
          billing: g[1].error ? 'Unable to load' : missing.length ? 'Incomplete' : 'Complete', missing: missing };
      });
    },
    /* Quotations and where each stands, as the client's Quotations reads
       them; one client's or every client's. */
    list_quotations: function (a) {
      if (!may('clients.quotes')) return Promise.resolve(noAccess('quotations', 'Clients'));
      var q = db.from('quotations').select('id, ref, client_id, brand, totals, status, source, issued_at, valid_until, removed_at, requested_at, ' +
        'proceed_at, proceed_due, replaces, released_at, reply_due, signed_at, submitted_at, reviewed_at, returned_at, declined_at, withdrawn_at, withdrawn_on, clients(name)')
        .is('removed_at', null);
      if (a.client_id) q = q.eq('client_id', a.client_id);
      return q.order('issued_at', { ascending: false }).limit(40).then(rows).then(function (list) {
        return fetched(['quotes']).then(function () { return list; });
      }).then(function (list) {
        var Q = window.ADspaceQuotes;
        var out = list.map(function (x) {
          var by = list.filter(function (y) { return y.replaces === x.id; })[0];
          x._lines = []; x._revised = by ? by.ref : null;
          var st = Q && Q.stateOf ? Q.stateOf(x) : [x.status];
          var t = x.totals || {}, cur = t.currency;
          return { quotation: x.ref, client: (x.clients && x.clients.name) || x.brand || null, state: st[0], issued: dayWord(x.issued_at),
            valid_until: x.valid_until ? dayWord(x.valid_until) : null,
            monthly_incl_sst: t.month && t.month.incl != null ? amt(t.month.incl, cur) : null,
            one_off_incl_sst: t.once && t.once.incl != null ? amt(t.once.incl, cur) : null,
            term_months: t.term || null, from_website: x.source === 'website',
            /* several brands on one quotation (2026-11-24) */
            brands: Array.isArray(t.brands) && t.brands.length > 1 ? t.brands.map(function (b) { return b.name; }) : null };
        });
        return { quotations: out.slice(0, 25), shown: Math.min(out.length, 25), found: out.length };
      });
    },
    /* Creator Campaigns: Payments, every creator's payment work. */
    creator_payments: function (a) {
      if (!may('campaigns.creators')) return Promise.resolve(noAccess('creator payments', 'Creators'));
      var from = CLOCK && CLOCK.addMonths ? CLOCK.addMonths(today().slice(0, 7) + '-01', -2) + '-01' : today().slice(0, 7) + '-01';
      if (/^\d{4}-\d{2}-\d{2}$/.test(String(a.paid_from || ''))) from = a.paid_from;
      return db.rpc('creator_payments_queue', { p_paid_from: from }).then(function (r) {
        var g = fnData(r, 'creator payments', 'Creators');
        if (g.refused) return g.refused;
        var d = g.data, pay = d.pay === true && may('campaigns.pay'), t = today();
        var job = function (j) {
          var b = j.bill || null, fee = pay && j.fee ? amt(j.fee.amount, j.fee.currency) : null;
          return { creator: j.name, creator_id: j.creator, job_reference: j.job || null, campaign: j.campaign || null, client: j.client || null,
            posted: j.posted_on ? dayWord(j.posted_on) : null, pay_by: j.pay_by ? dayWord(j.pay_by) : null,
            late: !!(b && b.status === 'processing' && j.pay_by && j.pay_by < t),
            fee: fee, bill: b ? b.number : null, bill_state: b ? BILL_STATE[b.status] || words2(b.status) : 'Not billed',
            bill_amount: pay && b && b.amount != null ? amt(b.amount, b.currency) : null,
            paid_on: b && b.status === 'paid' && (b.paid_on || b.date) ? dayWord(b.paid_on || b.date) : null };
        };
        var jobs = (d.jobs || []).map(job);
        var grp = function (k) { return jobs.filter(function (j) { return k === 'ready' ? j.bill_state === 'Not billed' : j.bill_state === k; }); };
        return {
          amounts_shown: pay,
          details_to_review: (d.review || []).map(function (x) { return { creator: x.name, creator_id: x.creator, submitted: dayWord(x.created_at), replaces_approved: !!x.replaces }; }),
          ready_to_bill: grp('ready'), draft_in_bukku: grp('Draft in Bukku'), awaiting_payment: grp('Awaiting payment'),
          paid_since: dayWord(from), paid: grp('Paid')
        };
      });
    },
    /* The Creators List: by name, Creator ID, platform or rate. */
    find_creators: function (a) {
      if (!may('campaigns.creators')) return Promise.resolve(noAccess('creators', 'Creators'));
      var plat = PLATFORM_KEY[String(a.platform || '').toLowerCase().trim()] || null;
      var q = db.from('creators').select('id, name, creator_code, client_rate, active, creator_profiles(platform)');
      var words0 = clean(a.query || '');
      if (words0.length >= 2) {
        var v = words0.replace(/_/g, '\\\\_');
        q = q.or('name.ilike."%' + v + '%",creator_code.ilike."%' + v + '%"');
      }
      if (a.min_rate != null && !isNaN(Number(a.min_rate))) q = q.gte('client_rate', Number(a.min_rate));
      if (a.max_rate != null && !isNaN(Number(a.max_rate))) q = q.lte('client_rate', Number(a.max_rate));
      return q.order('name').limit(200).then(rows).then(function (list) {
        var out = list.filter(function (c) {
          return (a.include_inactive || c.active !== false) &&
            (!plat || (c.creator_profiles || []).some(function (p) { return p.platform === plat; }));
        }).map(function (c) {
          var ps = [];
          (c.creator_profiles || []).forEach(function (p) { var w = PLATFORM_WORD[p.platform] || p.platform; if (ps.indexOf(w) < 0) ps.push(w); });
          return { creator_id: c.id, name: c.name, creator_id_code: c.creator_code || null, platforms: ps,
            rate: c.client_rate != null ? amt(c.client_rate) : null, active: c.active !== false };
        });
        return { creators: out.slice(0, 25), shown: Math.min(out.length, 25), found: out.length };
      });
    },
    /* One creator's bookings and where each one's payment stands, as the
       creator's Payment pane reads them. */
    creator_bookings: function (a) {
      if (!may('campaigns.creators')) return Promise.resolve(noAccess("a creator's bookings", 'Creators'));
      return db.rpc('creator_bills_list', { p_creator: a.creator_id }).then(function (r) {
        var g = fnData(r, "a creator's bookings", 'Creators');
        if (g.refused) return g.refused;
        var d = g.data, pay = d.pay === true && may('campaigns.pay');
        var bill = function (b) {
          return b ? { bill: b.number, state: BILL_STATE[b.status] || words2(b.status), amount: pay && b.amount != null ? amt(b.amount, b.currency) : null,
            paid_on: b.paid_on ? dayWord(b.paid_on) : null } : { state: 'Not billed' };
        };
        return { amounts_shown: pay, linked_to_bukku: !!d.linked,
          standard_fee: pay && d.standard_fee ? amt(d.standard_fee.amount, d.standard_fee.currency) : null,
          bookings: (d.jobs || []).map(function (j) {
            return { job_reference: j.job || null, campaign: j.campaign || null, campaign_id: j.campaign_id || null,
              step: CREATOR_STATE[j.state] || words2(j.state), posted: j.posted_on ? dayWord(j.posted_on) : null,
              pay_by: j.pay_by ? dayWord(j.pay_by) : null, fee: pay && j.fee ? amt(j.fee.amount, j.fee.currency) : null, payment: bill(j.bill) };
          }),
          earlier_bills: (d.earlier || []).slice(0, 10).map(bill) };
      });
    },
    /* Suppliers: who they are and where they stand; never bank details,
       an NRIC, a number or an email. */
    find_suppliers: function (a) {
      if (!may('suppliers')) return Promise.resolve(noAccess('suppliers', 'Suppliers'));
      return db.rpc('suppliers_list', {}).then(function (r) {
        var g = fnData(r, 'suppliers', 'Suppliers');
        if (g.refused) return g.refused;
        var q = clean(a.query || '').toLowerCase();
        var list = (g.data.rows || []).filter(function (s) { return !q || has(s.name, q) || has(s.code, q) || has(s.contact_name, q); });
        return { suppliers: list.slice(0, 20).map(function (s) {
          return { supplier_id: s.id, supplier_id_code: s.code, name: s.name || null, kind: s.kind === 'individual' ? 'Individual' : s.kind === 'company' ? 'Company' : null,
            status: { pending: 'Pending', active: 'Active', inactive: 'Inactive' }[s.status] || s.status, contact_person: s.contact_name || null,
            designation: s.designation || null, payment_term: s.payment_term || null, currency: s.currency === 'SGD' ? 'S$' : 'RM',
            details_waiting: !!s.waiting, approved: s.approved_at ? dayWord(s.approved_at) : null };
        }), shown: Math.min(list.length, 20), found: list.length };
      });
    },
    /* The Dashboard's figures, counted as its tiles count them: Delivered,
       On time, Oldest late and each colleague's (My Work: Reports), and
       New leads, Won, Lost and Churned (Clients at Full Access with Leads). */
    dashboard_figures: function (a) {
      var O = window.ADspaceOverview;
      if (!O || !O.span) return Promise.resolve({ error: 'unavailable' });
      var keys = (O.PERIODS || []).map(function (p) { return p[0]; });
      var p = keys.indexOf(a.period) > -1 ? a.period : 'month';
      var work = O.can.figures(), leads = O.can.leads();
      if (!work && !leads) return Promise.resolve(noAccess('the Dashboard figures', 'Dashboard'));
      var s = O.span(p), out = { period: s.name, compared_with: s.prevName };
      var who = a.person_id || null;
      var jobs = [];
      if (work) jobs.push(db.rpc('ops_reports', { p_ranges: [s.now, s.prev].map(function (r) { return { from: r.from.toISOString(), to: r.to.toISOString() }; }) })
        .then(function (r) {
          if (r.error || !Array.isArray(r.data)) throw r.error || new Error('');
          var now = r.data[0] || {}, prev = r.data[1] || {};
          var done = function (d) { return (d.by_person || []).reduce(function (x, y) { return x + (Number(y.completed) || 0); }, 0); };
          var rate = function (d) { var f = d.on_time || {}, n = Number(f.reached || 0) + Number(f.late_open || 0); return n ? Math.round(Number(f.met || 0) / n * 100) : null; };
          var late = now.late || [];
          var oldest = late.reduce(function (x, t) { return x && (Number(x.days_over) || 0) >= (Number(t.days_over) || 0) ? x : t; }, null);
          out.delivered = done(now); out.delivered_before = done(prev);
          out.on_time = rate(now) == null ? 'None due' : rate(now) + '%';
          out.on_time_before = rate(prev) == null ? 'None due' : rate(prev) + '%';
          out.late_now = late.length;
          out.oldest_late = oldest ? { task: oldest.title, client: oldest.client || null, days_late: Number(oldest.days_over) || 0 } : null;
          var people = {};
          (now.open_by_person || []).forEach(function (x) { if (x.team_member_id) people[x.team_member_id] = { name: x.name, open: Number(x.open) || 0, late: Number(x.late) || 0, delivered: 0, on_time: 0 }; });
          (now.by_person || []).forEach(function (x) {
            var id = x.team_member_id || x.id;
            if (!id) return;
            var q = people[id] || (people[id] = { name: x.name, open: 0, late: 0, delivered: 0, on_time: 0 });
            q.delivered = Number(x.completed) || 0; q.on_time = Number(x.on_time) || 0;
          });
          out.by_person = Object.keys(people).filter(function (k) { return !who || k === who; }).map(function (k) {
            var q = people[k];
            return { person_id: k, name: q.name, open: q.open, late: q.late, delivered: q.delivered,
              on_time: q.delivered ? Math.round(q.on_time / q.delivered * 100) + '%' : null };
          });
        }));
      else out.work_figures = noAccess('the work figures', 'Dashboard');
      if (leads) jobs.push(API.readPages(function () {
        return db.from('clients').select('id, name, slug, client_code, stage, stage_reason, stage_log, stage_since, created_at, source, owner, sales_by, market, bill_sgd').order('id');
      }).then(rows).then(function (cl) {
        return fetched(['sales']).then(function () { return cl; });
      }).then(function (cl) {
        var S = window.ADspaceSales, f = S.figures(cl, null, s.now), b = S.figures(cl, null, s.prev);
        var mine = function (list) { return who ? list.filter(function (c) { return c.sales_by === who; }) : list; };
        var names = function (list) { return mine(list).slice(0, 15).map(function (c) { return c.name; }); };
        out.new_leads = mine(f.newLeads).length; out.new_leads_before = mine(b.newLeads).length; out.new_lead_names = names(f.newLeads);
        out.won = mine(f.won).length; out.won_before = mine(b.won).length; out.won_names = names(f.won);
        out.lost_leads = mine(f.lost).length; out.churned = who ? null : f.churned.length;
        if (who) out.counted_by = 'Sales by';
      }));
      else out.lead_figures = noAccess('the lead figures', 'Dashboard');
      return Promise.all(jobs).then(function () { return out; });
    },
    /* Documents: letters and documents issued, by serial, recipient or
       client; HR Letters only where they are held. */
    find_documents: function (a) {
      var docs = may('register.documents') || may('register.hr'), offers = may('clients.documents');
      if (!docs && !offers) return Promise.resolve(noAccess('documents', 'Documents'));
      var v = clean(a.query || '').replace(/_/g, '\\\\_');
      var jobs = [];
      if (docs) {
        var q = db.from('documents').select('id, serial, kind, family, title, issued_at, voided_at, signed, client_id, recipient, clients(name)');
        if (!may('register.hr')) q = q.neq('family', 'hr');
        if (a.client_id) q = q.eq('client_id', a.client_id);
        if (v.length >= 2) q = q.or('serial.ilike."%' + v + '%",title.ilike."%' + v + '%",recipient->>name.ilike."%' + v + '%"');
        jobs.push(q.order('created_at', { ascending: false }).limit(20).then(rows).then(function (l) {
          return l.map(function (d) {
            return { reference: d.serial, document: d.title || words2(d.kind), family: DOC_FAMILY[d.family] || words2(d.family),
              client: (d.clients && d.clients.name) || null, to: mask(d.recipient && d.recipient.name) || null,
              issued: d.issued_at ? dayWord(d.issued_at) : null, state: d.voided_at ? 'Void' : d.signed === false ? 'Not signed' : 'Issued', _at: d.issued_at || '' };
          });
        }));
      }
      if (offers) {
        var o = db.from('client_documents').select('id, number, issued_at, voided_at, signed_at, client_id, clients(name)');
        if (a.client_id) o = o.eq('client_id', a.client_id);
        if (v.length >= 2) o = o.ilike('number', '%' + v + '%');
        jobs.push(o.order('created_at', { ascending: false }).limit(20).then(rows).then(function (l) {
          return l.map(function (d) {
            return { reference: d.number, document: 'Letter of Offer', family: 'Letter of Offer', client: (d.clients && d.clients.name) || null,
              issued: d.issued_at ? dayWord(d.issued_at) : null, state: d.voided_at ? 'Void' : d.signed_at ? 'Signed' : 'Issued', _at: d.issued_at || '' };
          });
        }));
      }
      return Promise.all(jobs).then(function (g) {
        var all = [].concat.apply([], g).sort(function (x, y) { return String(y._at).localeCompare(String(x._at)); });
        all.forEach(function (x) { delete x._at; });
        return { documents: all.slice(0, 25), shown: Math.min(all.length, 25) };
      });
    },
    /* Video Scripts. */
    list_scripts: function (a) {
      if (!may('scripts')) return Promise.resolve(noAccess('video scripts', 'Video Scripts'));
      var q = db.from('video_scripts').select('id, code, title, period, status, shoot_on, venue, client_id, clients(name)');
      if (a.client_id) q = q.eq('client_id', a.client_id);
      var v = clean(a.query || '').replace(/_/g, '\\\\_');
      if (v.length >= 2) q = q.or('code.ilike."%' + v + '%",title.ilike."%' + v + '%"');
      return q.order('created_at', { ascending: false }).limit(20).then(rows).then(function (l) {
        return { scripts: l.map(function (x) {
          return { script_id: x.id, code: x.code || null, title: x.title || null, client: (x.clients && x.clients.name) || null,
            month: x.period ? monthName(x.period) : 'No month', state: x.status === 'shared' ? 'Published' : 'Draft',
            shoot: x.shoot_on ? dayWord(x.shoot_on) : null, venue: x.venue || null };
        }) };
      });
    },
    /* Short Links. */
    find_links: function (a) {
      if (!may('links')) return Promise.resolve(noAccess('short links', 'Short Links'));
      var q = db.from('links').select('slug, title, target_url, active, created_at');
      var v = clean(a.query || '').replace(/_/g, '\\\\_');
      if (v.length >= 2) q = q.or('slug.ilike."%' + v + '%",title.ilike."%' + v + '%",target_url.ilike."%' + v + '%"');
      return q.order('created_at', { ascending: false }).limit(25).then(rows).then(function (l) {
        return { links: l.map(function (x) {
          return { short_link: x.slug, title: x.title || null, goes_to: x.target_url, state: x.active === false ? 'Paused' : 'Live' };
        }) };
      });
    },
    /* The Activity record: who changed what, the parts of it the colleague
       may read (its policy answers the rest with nothing). */
    activity_record: function (a) {
      if (!bridge.sectionAllowed || !bridge.sectionAllowed('activity')) return Promise.resolve(noAccess('the Activity record', 'Activity record'));
      var days = Math.max(1, Math.min(90, Number(a.days) || 14));
      var q = db.from('activity_log').select('created_at, actor, action, subject, detail').gte('created_at', new Date(Date.now() - days * 864e5).toISOString());
      var v = clean(a.query || '').replace(/_/g, '\\\\_');
      if (v.length >= 2) q = q.or('subject.ilike."%' + v + '%",detail.ilike."%' + v + '%"');
      return team().then(function () { return q.order('created_at', { ascending: false }).limit(60); }).then(rows).then(function (l) {
        var by = a.person_id ? nameOf(a.person_id) : '';
        var out = l.map(function (x) {
          var r = bridge.record ? bridge.record(x) : { who: '', what: x.action, on: x.subject, detail: x.detail };
          return { when: whenWord(x.created_at), who: r.who || 'System', what: r.what, on: mask(r.on) || null, detail: mask(r.detail) || null };
        }).filter(function (x) { return !by || x.who === by; });
        return { entries: out.slice(0, 40), days: days, shown: Math.min(out.length, 40) };
      });
    },
    /* Messages: the WhatsApp and Email logs, a month at a time, never a
       number or an address. */
    message_log: function (a) {
      if (!may('whatsapp')) return Promise.resolve(noAccess('messages sent', 'Messages'));
      var month = monthKey(a.month), email = a.channel === 'email', q = clean(a.query || '').toLowerCase();
      return db.rpc(email ? 'mail_log' : 'wa_messages', { p_month: month }).then(function (r) {
        var g = fnData(r, 'messages sent', 'Messages');
        if (g.refused) return g.refused;
        var items = g.data.items || [];
        var list = email ? items.map(function (x) {
          return { to: mask(x.to_name) || 'A deleted address', client: x.client || null, supplier: x.supplier || null, email: x.subject || null,
            reference: x.reference || null, sent_by: x.sent_by || 'Automatic', status: MAIL_STATE[x.status] || words2(x.status),
            when: whenWord(x.sent_at || x.created_at) };
        }) : items.map(function (x) {
          return { to: mask(x.to_name) || null, client: x.client || null, what: WA_PURPOSE[x.purpose] || words2(x.purpose), template: x.template || null,
            sent_by: x.created_by || 'Automatic', status: waState(x), when: whenWord(x.created_at) };
        });
        if (q) list = list.filter(function (x) { return JSON.stringify(x).toLowerCase().indexOf(q) > -1; });
        return { channel: email ? 'Email' : 'WhatsApp', month: monthName(month), messages: list.slice(0, 40), shown: Math.min(list.length, 40), found: list.length };
      });
    },
    /* The Handbook: every colleague reads it. */
    handbook: function (a) {
      var q = db.from('handbook_docs').select('id, title, category, summary, required, updated_at').is('archived_at', null);
      var v = clean(a.query || '').replace(/_/g, '\\\\_');
      if (v.length >= 2) q = q.or('title.ilike."%' + v + '%",summary.ilike."%' + v + '%"');
      return q.order('title').limit(30).then(rows).then(function (l) {
        return { documents: l.map(function (x) {
          return { title: x.title, category: HB_CAT[x.category] || words2(x.category), summary: mask(x.summary) || null,
            must_read: !!x.required, updated: x.updated_at ? dayWord(x.updated_at) : null };
        }) };
      });
    },
    /* Every section at once, as console search finds a record: the
       fallback for a question no other read answers. A result opens with
       open_page kind result. */
    search_portal: function (a) {
      var S = window.ADspaceSearch;
      if (!S || !S.find) return Promise.resolve({ error: 'unavailable' });
      return S.find(a.query).then(function (r) {
        return { groups: r.groups.map(function (g) {
          return { section: g.head, results: g.rows.map(function (x) {
            var key = 'r' + (++foundN);
            found[key] = x.open;
            return { result: key, name: mask(x.name), code: x.code || null,
              about: (x.meta || []).filter(function (m) { return m != null && String(m).trim(); }).map(mask).join(' · ') || null };
          }) };
        }), could_not_read: r.failed };
      });
    }
  });

  function reportRow(r) {
    return { report_id: r.id, client: (r.clients && r.clients.name) || null, brand: r.brand_name || null,
      kind: REPORT_KIND[r.kind] || r.kind, period: dayWord(r.period_start) + ' to ' + dayWord(r.period_end),
      status: REPORT_STATE[r.status] || r.status, sent: r.sent_on ? dayWord(r.sent_on) : (r.status === 'published' ? 'Not sent' : null) };
  }

  /* ---- The changes: drawn first, written only on Confirm --------------------- */
  function idem() { return 'ag-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8); }
  /* A row a card makes carries an id the page chose, once for the card: a
     second Confirm after a lost answer meets the row already made (23505)
     and goes on as made, never inserting again (review 2026-11-24). */
  function rowId(a) {
    if (a._rowId) return a._rowId;
    var c = window.crypto;
    if (c && c.randomUUID) return (a._rowId = c.randomUUID());
    var b = new Uint8Array(16);
    if (c && c.getRandomValues) c.getRandomValues(b); else for (var i = 0; i < 16; i++) b[i] = Math.floor(Math.random() * 256);
    b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128;
    var h = Array.prototype.map.call(b, function (x) { return (x < 16 ? '0' : '') + x.toString(16); }).join('');
    return (a._rowId = h.slice(0, 8) + '-' + h.slice(8, 12) + '-' + h.slice(12, 16) + '-' + h.slice(16, 20) + '-' + h.slice(20));
  }
  /* Made, or made already by an earlier press of this card. */
  function madeOnce(r) {
    if (r.error && r.error.code === '23505') return true;
    if (r.error) throw new Error(r.error.message);
    if (!(r.data || []).length) throw new Error('Not saved. The database refused the request.');
    return false;
  }
  /* What follows a row made (a line filed, a stage moved) never fails the
     act: the row stands, so Confirm is not offered again. */
  function after(p) { return Promise.resolve().then(p).catch(function () {}); }
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
        row.id = rowId(a);
        return db.from('client_touches').insert(row).select('id').then(function (r) {
          var again = madeOnce(r);
          var id = row.id, c = a._client;
          if (!again) after(function () {
            if (bridge.log) bridge.log('client.touch', c, (KIND[a.kind] || a.kind) + (a.next_action ? ' · next: ' + a.next_action : ''));
            file('assistant.call', c.name, (KIND[a.kind] || a.kind) + ' logged');
          });
          /* The first call or visit is what makes a lead contacted, as the
             Calls and visits pane does. */
          var moved = (c.stage || 'lead') === 'lead'
            ? after(function () {
              return db.from('clients').update({ stage: 'contacted' }).eq('id', c.id).eq('stage', 'lead').select('id').then(function (q) {
                /* An empty answer is a client already past Lead; an error is
                   a stage left unmoved, said with Saved. */
                if (q.error) return 'stuck';
                if (!(q.data || []).length || !bridge.log) return;
                return fetched(['crm']).then(function () {
                  var CRM = window.ADspaceCRM;
                  bridge.log('client.stage', c, CRM && CRM.contactedWord ? CRM.contactedWord(c) : 'Contacted');
                });
              });
            })
            : Promise.resolve();
          return moved.then(function (left) {
            return { said: left === 'stuck' ? 'Saved. The stage was not moved to Contacted. Change the stage on the client\'s record.' : 'Saved.', open: { kind: 'client', id: c.slug || c.id, pane: 'calls', label: 'Open Calls and visits' },
              undo: function () {
                return db.from('client_touches').update({ archived_at: new Date().toISOString() }).eq('id', id).select('id').then(function (q) {
                  if (q.error || !(q.data || []).length) throw new Error('Not undone. The database refused the request.');
                  if (bridge.log) bridge.log('client.touch_removed', c, KIND[a.kind] || a.kind);
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
          if (!e) throw new Error('That client has no content month for ' + monthName(a.month) + ' in My Work. Add the month first.');
          if (e.status === 'cancelled' || e.status === 'completed') throw new Error('That month is ' + (e.status === 'cancelled' ? 'Cancelled' : 'Completed') + '. Reopen it in My Work first.');
          var lead = a.led_by || (me() || {}).id;
          if (a.led_by && !nameOf(a.led_by)) throw new Error('That colleague could not be found. Ask again with their name.');
          a._client = c; a._eng = e; a._at = at; a._mins = mins; a._lead = lead; a._google = google;
          return [['Client', c.name + (c.client_code ? ' · ' + c.client_code : '')], ['Month', monthName(e.period)],
                  ['When', whenWord(at.toISOString()) + ' to ' + CLOCK.clock(new Date(at.getTime() + mins * 60000).toISOString())],
                  ['Channel', google ? 'Google Meet' : 'On site'], ['Led by', lead === (me() || {}).id ? 'You' : nameOf(lead)],
                  e.meeting_at && !e.meeting_na ? ['Current meeting', whenWord(e.meeting_at)] : null];
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
                ? meet('delete').then(function (d) { if (d && d.error) throw new Error('Not undone. The Google Meet could not be removed. Remove it in Google Calendar.'); })
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
        if (!(slots >= 1 && slots <= 200) || Math.floor(slots) !== slots) return Promise.reject(new Error('Enter at least one creator.'));
        return Promise.all([team(), db.from('clients').select('id, name, client_code, stage').eq('id', a.client_id).maybeSingle()]).then(function (g) {
          var c = g[1].data;
          if (!c) throw new Error('That client could not be found.');
          if (c.stage !== 'active') throw new Error('A campaign needs an Active client. Make the client Active first.');
          if (a.person_in_charge && !nameOf(a.person_in_charge)) throw new Error('That colleague could not be found. Ask again with their name.');
          a._client = c; a._title = title; a._slots = slots;
          a._owner = a.person_in_charge ? nameOf(a.person_in_charge) : (me() || {}).name || '';
          return [['Client', c.name + (c.client_code ? ' · ' + c.client_code : '')], ['Title', title], ['Creators', String(slots)],
                  ['Person in charge', a.person_in_charge && a.person_in_charge !== (me() || {}).id ? a._owner : 'You'],
                  ['Format', FORMAT[a.format] || 'Site visit'], ['State', 'Draft · No creators']];
        });
      },
      run: function (a) {
        var cid = rowId(a);
        return db.from('campaigns').insert({
          id: cid, client_id: a._client.id, title: a._title, purpose: null, slots: a._slots, deadline: null,
          push_format: FORMAT[a.format] ? a.format : 'site_visit', deliverable: a.deliverable === 'graphic' ? 'graphic' : 'video',
          owner: a._owner || null, backups_open: false, access_token: API.accessToken(), state: 'draft',
          created_by: (bridge.actor && bridge.actor()) || null
        }).select('id').then(function (r) {
          if (!madeOnce(r)) after(function () {
            if (bridge.log) bridge.log('campaign.created', a._title, a._slots + ' creators');
            file('assistant.campaign', a._title, 'Campaign created for ' + a._client.name);
          });
          return { said: 'Created.', open: { kind: 'campaign', id: cid, label: 'Open campaign' } };
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
              if (code === 'recent') throw new Error(W.line.sentRecently);
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
            if (q.error) throw new Error('That set could not be read. Try again.');
            var n = ((q.data || [])[0] || {}).n_posts || 0;
            if (on && !n) throw new Error('That set has no posts. Add assets before publishing.');
            a._set = b;
            return [['Set', b.title + ' · ' + n + (n === 1 ? ' post' : ' posts')], ['Client', (b.clients && b.clients.name) || ''],
                    ['Change', on ? 'Draft → Published' : 'Published → Draft'],
                    ['Review link', on ? 'Shown at once' : 'Removed']];
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
      if (prep.error) throw new Error(X.said ? X.said({ code: prep.error }) : 'This message cannot be sent. Send it from Messages.');
      var meta = g[1] || {}, set = g[2] || {};
      if (meta.error) throw new Error(X.said ? X.said(meta.error) : 'The templates could not be read. Try again.');
      var list = (meta.list || []).filter(function (t) { return t.supported; });
      var mine = (set.list || []).filter(function (t) { return t.purpose === purpose && t.active && t.name; })[0];
      var tpl = a.template ? list.filter(function (t) { return t.name === a.template; })[0]
        : mine ? list.filter(function (t) { return t.name === mine.name && t.language === mine.lang; })[0] : null;
      if (!tpl) {
        if (purpose === 'message' || a.template) {
          state.notes.push('The templates the portal can send are: ' + list.filter(function (t) { return t.header !== 'DOCUMENT'; }).map(function (t) { return t.name; }).join(', ') + '.');
          throw new Error(a.template ? 'That template is not approved for the portal. Choose another.' : 'Name the template to send.');
        }
        throw new Error('The WhatsApp template for this message is off. Please ask an admin to turn it on in Settings.');
      }
      if (tpl.header === 'DOCUMENT' || tpl.header_var) throw new Error('This template includes a file or a header. Send it from the report, quotation or letter it belongs to.');
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
                   warn: rec ? W.line.sentRecently : '', go: rec ? 'Send again' : 'Send' };
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
    'bad-condition': 'That condition cannot be checked. Ask again without it.', 'bad-payload': 'Some details are missing. Ask again with the name, the date and the time.',
    'too-many': 'You have 50 scheduled actions. Cancel one under Scheduled first.', 'wa-off': 'The WhatsApp template for this message is off. Please ask an admin to turn it on in Settings.',
    'not-found': 'That set, report or task no longer exists.', 'bad-kind': 'That cannot be scheduled. Ask for a reminder, a task, a report, a set or a WhatsApp message.' };
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
    if (a.condition && !a._cref) return Promise.reject(new Error('Name the set, report or task the condition is about.'));
    var when = ['When', whenWord(at.toISOString())];
    var only = a.condition ? ['Condition', COND[a.condition]] : null;
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
        if (on && /holds no posts/.test(e.message)) return [['Set', 'No posts']];
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
  /* A section by the name Claude is given (2026-11-19: the fallback names
     the section that holds the answer and opens it): its address, its
     route, and the key a colleague must hold beyond the route. */
  var PLACES = {
    dashboard: ['/admin/?s=dashboard', 'overview'], analytics: ['/admin/?s=analytics', 'analytics'],
    my_work: ['/admin/?s=work', 'work'], clients: ['/admin/?s=clients', 'clients'],
    overdue_invoices: ['/admin/?s=clients&view=overdue', 'clients', 'clients.billing'],
    content_review: ['/admin/?s=review', 'review'], video_scripts: ['/admin/?s=scripts', 'scripts'],
    creator_campaigns: ['/admin/?s=campaigns', 'campaigns'], creators: ['/admin/?s=campaigns&tab=roster', 'campaigns', 'campaigns.creators'],
    creator_payments: ['/admin/?s=campaigns&tab=payments', 'campaigns', 'campaigns.creators'],
    reports: ['/admin/?s=reports', 'reports'], whatsapp: ['/admin/?s=whatsapp', 'whatsapp'], email_log: ['/admin/?s=whatsapp&tab=email', 'whatsapp'],
    documents: ['/admin/?s=register', 'register'], suppliers: ['/admin/?s=suppliers', 'suppliers'], short_links: ['/admin/?s=links', 'links'],
    services: ['/admin/?s=services', 'services'], team: ['/admin/?s=team', 'team'], hiring: ['/admin/?s=team&tab=hiring', 'team'],
    handbook: ['/admin/?s=handbook', 'handbook'], settings: ['/admin/?s=settings', 'settings'], my_records: ['/admin/?s=mine', 'mine'],
    activity_record: [null, 'activity']
  };
  /* Whether the colleague may open where a button would go: a section by
     its route's own rule, a record by its section. */
  var KIND_ROUTE = { client: 'clients', client_month: 'work', task: 'work', report: 'reports', set: 'review', script: 'scripts',
    campaign: 'campaigns', creator: 'campaigns', supplier: 'suppliers', my_work: 'work', dashboard: 'overview' };
  function mayOpen(o) {
    var ok = function (route) { return !bridge.sectionAllowed || bridge.sectionAllowed(route); };
    if (o.kind === 'result') return Boolean(found[o.id]);
    if (o.kind === 'section') { var pl = PLACES[o.id]; return Boolean(pl) && ok(pl[1]) && (!pl[2] || may(pl[2])); }
    if (o.kind === 'creator' && !may('campaigns.creators')) return false;
    return ok(KIND_ROUTE[o.kind] || 'work');
  }
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
      case 'creator': return ['/admin/?s=campaigns&tab=roster&creator=' + id, 'campaigns'];
      case 'supplier': return ['/admin/?s=suppliers&supplier=' + id, 'suppliers'];
      case 'section': return PLACES[o.id] || ['/admin/?s=work', 'work'];
      case 'dashboard': return ['/admin/?s=dashboard', 'overview'];
      default: return ['/admin/?s=work', 'work'];
    }
  }
  function openRecord(o) {
    if (!mayOpen(o)) return;
    if (SHEET.isOpen(box)) SHEET.close();
    /* A search result opens as search opens it; the Activity record is the
       sheet its mark at the rail's foot opens. */
    if (o.kind === 'result') { found[o.id](); return; }
    if (o.kind === 'section' && o.id === 'activity_record') { var mark = $('activityOpen'); if (mark) mark.click(); return; }
    if (o.kind !== 'my_work' && o.kind !== 'dashboard' && o.kind !== 'section' && !o.id) return;
    var to = addressOf(o);
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
    b.innerHTML = esc(o.label || 'Open') + ' ' + window.ADspaceIcons.glyph('chevron');
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
      /* An act done once answers as done: a press after its card was
         drawn as done never runs it again. */
      (a._done ? Promise.resolve(a._done) : def.run(a)).then(function (out) {
        a._done = out;
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
  /* Kept by count and by size (review 2026-11-24: forty long steps passed
     the function's 120,000 characters and every question after was
     refused): the oldest whole questions go until the rest is under
     TRIM_CHARS, the last question always kept. */
  var TRIM_CHARS = 100000;
  function sizeOfMsgs(list) {
    var n = 0;
    list.forEach(function (m) {
      if (typeof m.content === 'string') { n += m.content.length; return; }
      (m.content || []).forEach(function (b) {
        ['text', 'thinking', 'data', 'content'].forEach(function (k) { if (typeof b[k] === 'string') n += b[k].length; });
        if (b.input != null) n += JSON.stringify(b.input).length;
      });
    });
    return n;
  }
  function isQuestion(m) {
    return m.role === 'user' && m.content.some(function (b) { return b.type === 'text'; }) &&
      !m.content.some(function (b) { return b.type === 'tool_result'; });
  }
  function trim() {
    var i = Math.max(0, state.messages.length - 40);
    while (i < state.messages.length && !isQuestion(state.messages[i])) i++;
    var list = state.messages.slice(i);
    while (list.length && sizeOfMsgs(list) > TRIM_CHARS) {
      var j = 1;
      while (j < list.length && !isQuestion(list[j])) j++;
      if (j >= list.length) { list = []; break; }
      list = list.slice(j);
    }
    state.messages = list;
  }
  function step(n) {
    busy(true);
    var mine = ++state.said;
    db.functions.invoke('portal-agent', { body: { messages: state.messages, press: state.press || undefined } }).then(function (res) {
      if (mine !== state.said) return;
      var d = res.data;
      if (typeof d === 'string') { try { d = JSON.parse(d); } catch (e) { d = null; } }
      if (res.error || !d) {
        /* Refused as too long (400): the conversation is cleared by its own
           control, never sent again as it stands. */
        return window.ADspaceAPI.fnRefusal(res).then(function (code) {
          if (mine !== state.said) return;
          fail(code === 'bad-request' ? SAID['too-long'] : 'The Assistant could not be reached. Try again.');
        });
      }
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
      /* A button is drawn only where the colleague may open it; else
         Claude is told, and says so. */
      if (!(a.kind === 'my_work' || a.kind === 'dashboard' || a.id)) return Promise.resolve(result(use, { error: 'id required' }, true));
      if (!mayOpen(a)) return Promise.resolve(result(use, a.kind === 'result' ? { error: 'not-found' } : noAccess('this page', null), false));
      add('', 'ag-ai ag-opens').appendChild(openBtn(a));
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
    /* AI off for the portal or the group (GROUP SWITCHES, 2026-11-17). */
    if (document.documentElement.classList.contains('no-ai')) return;
    /* AI off for the portal, or the day's questions used: ⌘ J and a
       question typed on the Dashboard say why from the Ask button, as a
       press on it does (SWITCHED-OFF ACTS, 2026-11-21). */
    var A = window.ADspaceAdmin;
    if (A && A.gateState && !A.gateState('ai:agent').on) { if (A.gateWhy) A.gateWhy(btn); return; }
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

  window.ADspaceAgent = { open: open, ask: function (t) { var A = window.ADspaceAdmin; open(); if (!(A && A.gateState && !A.gateState('ai:agent').on)) ask(t); }, _tools: { read: READ, change: CHANGE }, scheduled: readSched };
})();
