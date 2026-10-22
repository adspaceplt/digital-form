/*
 * The Dashboard (`?s=dashboard`) — the start page for a group that manages a
 * section, built from the mockup the user approved (2026-10-12, task 47).
 *
 * One page read top to bottom, never a tab a section: the period (This
 * month, Last month, This quarter); what needs acting on today beside the
 * share of work that reached the client on time; Sales and Operations as
 * tiles, each a figure, its change on the period before and its trend; the
 * charts that answer faster than a table; then one list of everything
 * waiting, late first, each row opening its record.
 *
 * Every tile, chart, signal and list source asks its own permission before
 * it reads anything, at Full Access on its section or part, the granted
 * parts at their grant (2026-10-03), so what a group may not oversee is not
 * drawn and nothing of it is read. Reads are shared within a visit (one
 * request a source, whatever draws from it) and made again on the next
 * visit, never polled. Committed monthly value is the one money figure
 * (2026-10-12): drawn for whoever may open a client's Services
 * (`clients.services` at View), read from the lines that part already
 * opens; anyone else reads Active clients in that tile.
 */
(function () {
  var API = window.ADspaceAPI;
  var db = API && API.client;
  var UI = window.ADspaceState;
  var CH = window.ADspaceChart;
  var bridge = window.ADspaceAdmin || {};
  if (!API || !API.configured || !db || !UI || !CH) return;
  var W = (window.ADspaceWords && window.ADspaceWords.en) || {};

  function $(id) { return document.getElementById(id); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  /* Full Access (manage) on a section or its part opens its tiles and cards
     (the user, 2026-10-03); the granted parts (ops.reports, ops.all,
     team.performance) are asked at their grant. */
  function may(key, lv) { return Boolean(bridge.may && bridge.may(key, lv || 'view')); }

  /* Every day, month and period is Malaysia's (js/clock.js), whatever the
     device's clock, and so are the months' names. */
  var CK = window.ADspaceClock, MON = CK.MON, LONG = CK.LONG;
  function pad2(n) { return String(n).padStart(2, '0'); }
  function today() { return CK.start(CK.today()); }
  // Whole days from a date to today; a future date is 0.
  function daysSince(v) {
    var d = v ? CK.day(v) : '';
    return d ? Math.max(0, CK.between(d, CK.today())) : 0;
  }
  var RESTRICT_WORD = { instagram: 'Instagram', facebook: 'Facebook', tiktok: 'TikTok', xhs: 'rednote', other: 'Other account' };
  function daysWord(n) { return n === 1 ? '1 day' : n + ' days'; }
  function sinceWord(v) { var n = daysSince(v); return n ? daysWord(n) : 'Today'; }
  function dateWord(v) { return v ? CK.date(v) : ''; }
  // A date in this year without its year: "7 Oct"; another year keeps it.
  function shortDate(v) {
    var d = v ? CK.day(v) : '';
    if (!d) return '';
    return d.slice(0, 4) === CK.today().slice(0, 4) ? CK.date(d, { year: false }) : dateWord(d);
  }
  // Last month: its first day, its last day, its name and its address key.
  function lastMonth() {
    var key = CK.addMonths(CK.today(), -1), mo = Number(key.slice(5, 7)) - 1;
    return { start: CK.start(key + '-01'), end: CK.start(CK.addDays(CK.addMonths(key, 1) + '-01', -1)), mo: mo,
             word: LONG[mo] + ' ' + key.slice(0, 4), short: MON[mo], key: key };
  }
  function isoDay(d) { return CK.day(d); }
  var CHEV = '<svg class="ovgo-chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
    'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 18l6-6-6-6"/></svg>';

  /* A read that answers `{ error }` from a function after the page's own
     check passed is a refusal, and a refusal is never drawn as nothing. */
  function rows(r) {
    if (!r || r.error) throw new Error((r && r.error && r.error.message) || 'The read was refused.');
    if (r.data && r.data.error) throw new Error(r.data.error === 'denied' ? 'Not allowed for this group.' : String(r.data.error));
    return r.data;
  }

  // ---- Where a row goes ------------------------------------------------------
  /* The record's address first, then the section, as console search does, so
     the section opens on the record rather than on its list. */
  function go(url, section) {
    history.replaceState(null, '', url);
    if (section === 'review' && bridge.restore) bridge.restore();
    else if (bridge.show) bridge.show(section);
  }
  function clientUrl(c, tab) {
    var key = (c && (c.slug || c.id)) || '';
    return '/admin/?client=' + encodeURIComponent(key) + (tab ? '&tab=' + tab : '');
  }

  // ---- The period ------------------------------------------------------------
  /* Every figure on the page reads the period chosen; the reports owed and
     the reviews are last month's whatever it is, as their titles say. Each
     period is [from, to): every one but Last month runs to now, and the one
     before it is the same length on the same days. */
  /* Last quarter and This year joined on the user's word (2026-10-12):
     five choices, so a select, never a segment. */
  var PERIODS = [['month', 'This month'], ['last', 'Last month'], ['quarter', 'This quarter'],
                 ['lastq', 'Last quarter'], ['year', 'This year']];
  var period = 'month';
  /* The same Malaysian day and time n months on, the day held to the
     month's last. */
  function addMonths(d, n) {
    var p = CK.parts(d), key = CK.addMonths(CK.day(d), n);
    var last = Number(CK.addDays(CK.addMonths(key, 1) + '-01', -1).slice(8, 10));
    var at = CK.at(key + '-' + pad2(Math.min(p.d, last)), pad2(p.h) + ':' + pad2(p.mi));
    return new Date(at.getTime() + ((d.getTime() % 60000) + 60000) % 60000);
  }
  function rangeOf(p) {
    var now = new Date(), t = CK.today(), m0 = CK.start(t.slice(0, 7) + '-01');
    if (p === 'last') return { from: CK.start(CK.addMonths(t, -1) + '-01'), to: m0 };
    var qKey = t.slice(0, 4) + '-' + pad2(Math.floor((Number(t.slice(5, 7)) - 1) / 3) * 3 + 1);
    var q0 = CK.start(qKey + '-01');
    if (p === 'quarter') return { from: q0, to: now };
    if (p === 'lastq') return { from: CK.start(CK.addMonths(qKey, -3) + '-01'), to: q0 };
    if (p === 'year') return { from: CK.start(t.slice(0, 4) + '-01-01'), to: now };
    return { from: m0, to: now };
  }
  function prevOf(p) {
    var r = rangeOf(p), n = p === 'quarter' || p === 'lastq' ? 3 : p === 'year' ? 12 : 1;
    return { from: addMonths(r.from, -n), to: addMonths(r.to, -n) };
  }
  function quarterWord(d) { var p = CK.parts(d); return 'Q' + (Math.floor(p.mo / 3) + 1) + ' ' + p.y; }
  // What a change is measured against, in a word: "on Sept", "on last quarter".
  function prevWord(p) {
    if (p === 'quarter') return 'last quarter';
    if (p === 'lastq') return quarterWord(prevOf(p).from);
    if (p === 'year') return 'last year';
    return MON[CK.parts(prevOf(p).from).mo];
  }
  // The period in words: "1 to 12 Oct 2026", "Sept 2026", "1 Jul to 12 Oct 2026".
  function spanWord(r) {
    var a = CK.parts(r.from), b = CK.parts(r.to.getTime() - 1), z = CK.parts(r.to);
    var whole = a.d === 1 && z.d === 1 && z.h === 0 && z.mi === 0;
    if (whole && a.mo === b.mo) return MON[a.mo] + ' ' + a.y;
    if (a.mo === b.mo) return a.d + ' to ' + b.d + ' ' + MON[a.mo] + ' ' + a.y;
    return a.d + ' ' + MON[a.mo] + ' to ' + b.d + ' ' + MON[b.mo] + ' ' + b.y;
  }
  function periodName(p) {
    return p === 'last' ? MON[CK.parts(rangeOf('last').from).mo] : p === 'quarter' ? 'this quarter'
      : p === 'lastq' ? quarterWord(rangeOf('lastq').from) : p === 'year' ? 'this year' : 'this month';
  }
  function delta(now, before) {
    var d = now - before;
    if (!d) return 'Same as ' + prevWord(period);
    return (d > 0 ? '+' : '−') + Math.abs(d) + ' on ' + prevWord(period);
  }

  // ---- Reads, one request each a visit ----------------------------------------
  var memo = {};
  function once(key, fn) {
    if (!memo[key]) {
      memo[key] = Promise.resolve().then(fn);
      memo[key].catch(function () { delete memo[key]; });
    }
    return memo[key];
  }
  /* The period, the period before it and, once a visit, each of the last
     six months (the on-time line, what was delivered each month): one
     request (`ops_reports`, ops_report's own answer for each span; the third
     audit, item 19), never a call a span. */
  function reports() {
    return once('rep:' + period, function () {
      var want6 = !memo.rep6, ms = CH.months(6);
      var spans = [rangeOf(period), prevOf(period)].concat(want6 ? ms.map(function (m) { return { from: m.start, to: m.end }; }) : []);
      var all = db.rpc('ops_reports', { p_ranges: spans.map(function (r) { return { from: r.from.toISOString(), to: r.to.toISOString() }; }) })
        .then(rows).then(function (l) {
          if (!Array.isArray(l)) throw new Error('The read was refused.');
          l.forEach(function (d) { rows({ data: d }); });
          return l;
        });
      if (want6) {
        memo.rep6 = all.then(function (l) { return ms.map(function (m, i) { return { m: m, d: l[i + 2] || {} }; }); });
        memo.rep6.catch(function () { delete memo.rep6; });
      }
      return all.then(function (l) { return { now: l[0] || {}, prev: l[1] || {} }; });
    });
  }
  var R = {
    report: function () { return reports().then(function (x) { return x.now; }); },
    reportPrev: function () { return reports().then(function (x) { return x.prev; }); },
    months: function () { return memo.rep6 || reports().then(function () { return memo.rep6 || Promise.reject(new Error('The read was refused.')); }); },
    /* Every client the group reads, once: the sales figures, leads going
       cold, the pipeline and restricted accounts all draw from it. */
    clients: function () {
      return once('clients', function () {
        return API.readPages(function () {
          return db.from('clients').select('id, name, slug, stage, stage_reason, stage_log, stage_since, created_at, source, owner, market, bill_sgd, ' +
            'restricted_platform, restricted_since, restricted_note').order('id');
        }).then(rows).then(function (l) { return l || []; });
      });
    },
    lines: function () {
      return once('lines', function () {
        return API.readPages(function () {
          return db.from('client_services').select('id, client_id, qty, rate, tenure, start_on, term_adjust, term_pct, state, archived_at').order('id');
        }).then(rows).then(function (l) { return l || []; });
      });
    },
    openTasks: function () {
      return once('open', function () {
        return API.readPages(function () {
          return db.from('ops_tasks').select('id, task_no, title, current_final_due_at, client_id, clients(name, stage)')
            .is('completed_at', null).is('cancelled_at', null).is('archived_at', null).order('id');
        }).then(rows).then(function (l) { return l || []; });
      });
    },
    owed: function () {
      return once('owed', function () {
        return db.rpc('sm_reports_owed', { p_period: lastMonth().key }).then(rows).then(function (d) { return (d && d.items) || []; });
      });
    },
    inReview: function () {
      return once('review', function () {
        return db.from('sm_reports').select('id, kind, title, period_start, period_end, submitted_at, client_id, clients(name, owner)')
          .eq('status', 'review').order('submitted_at', { ascending: true }).then(rows).then(function (l) { return l || []; });
      });
    },
    requests: function () {
      return once('requests', function () {
        return db.from('client_requests').select('id, kind, service_label, state, created_at, client_id, clients(id, name, slug, owner)')
          .in('state', ['requested', 'reviewing']).is('withdrawn_at', null).order('created_at', { ascending: true })
          .then(rows).then(function (l) { return l || []; });
      });
    },
    /* Published sets with posts the client has not approved on the round on
       show (a revised post waits on the client again; a team approval taken
       back no longer stands). */
    sets: function () {
      return once('sets', function () {
        /* Every published set, paged, never the newest few: an older set
           still waiting on its client stays on the list (2026-10-20). */
        return API.readPages(function () {
          return db.from('batches').select('id, title, client_id, published_at, created_at, clients(id, name, slug, owner)')
            .eq('published', true).order('created_at', { ascending: false }).order('id');
        }).then(rows).then(function (sets) {
            sets = sets || [];
            if (!sets.length) return [];
            /* Counted by the database for every set in one request
               (`review_set_counts`): a read of every post and decision passed
               a thousand ids in the address and stopped at a thousand rows. */
            return db.rpc('review_set_counts', { p_sets: sets.map(function (s) { return s.id; }) }).then(rows).then(function (counts) {
              var by = {};
              (counts || []).forEach(function (c) { by[c.set_id] = c; });
              return sets.map(function (s) {
                var c = by[s.id] || {};
                return { s: s, n: c.n_posts || 0, ok: c.n_approved || 0, ch: c.n_changes || 0 };
              }).filter(function (x) { return x.n && x.ok < x.n; });
            });
          });
      });
    },
    noSet: function () {
      return once('noset', function () {
        var first = CK.start(CK.today().slice(0, 7) + '-01');
        /* The sets of the last twelve months, never every set ever made (the
           third audit, item 19): enough for "Last set" on a client gone quiet
           within the year; quieter than that reads "No set this month" alone. */
        var since = CK.start(CK.addMonths(CK.today(), -12) + '-01');
        return Promise.all([
          db.from('clients').select('id, name, slug, owner').eq('stage', 'active').eq('review_hidden', false).order('name').then(rows),
          db.from('batches').select('client_id, created_at').gte('created_at', since.toISOString()).order('created_at', { ascending: false }).then(rows)
        ]).then(function (r) {
          var last = {};
          (r[1] || []).forEach(function (b) { if (!last[b.client_id]) last[b.client_id] = b.created_at; });
          return (r[0] || []).filter(function (c) { return !last[c.id] || new Date(last[c.id]) < first; })
            .map(function (c) { return { c: c, last: last[c.id] || null }; });
        });
      });
    },
    /* Every open booking a campaign holds, once: the bookings chart, those
       past their date and those waiting for the quality check. */
    bookings: function () {
      return once('bookings', function () {
        return db.from('campaign_options')
          .select('id, state, visit_date, submission_due, submitted_at, campaign_id, campaigns(id, title, owner, client_id), creators(name)')
          .in('state', ['pending_visit', 'pending_draft', 'changes', 'submitted', 'reviewing', 'scheduled'])
          .then(rows).then(function (l) { return l || []; });
      });
    },
    letters: function () {
      return once('letters', function () {
        return db.from('client_documents').select('id, number, issued_at, client_id, clients(id, name, slug, owner)')
          .in('kind', ['offer', 'intent', 'cover']).is('signed_at', null).is('voided_at', null).is('superseded_by', null)
          .order('issued_at', { ascending: true }).then(rows).then(function (l) { return l || []; });
      });
    },
    reviews: function () {
      return once('perf', function () {
        return db.rpc('perf_overview', { p_period: lastMonth().key + '-01' }).then(rows).then(function (d) { return (d && d.rows) || []; });
      });
    }
  };

  // ---- The sales figures --------------------------------------------------------
  /* Worked out by the Sales view's own rules (`ADspaceSales.figures`), so the
     Dashboard and Clients · Sales never disagree. */
  var S = function () { return window.ADspaceSales; };
  /* The period (`now`), the one before it (`prev`) or the last six months
     (`six`), worked out once a visit and period, whatever draws from it. */
  function figuresFor(which, lines) {
    return once('fig:' + period + ':' + which + (lines ? ':lines' : ''), function () {
      var r = which === 'prev' ? prevOf(period) : which === 'six' ? sixMonths() : rangeOf(period);
      return R.clients().then(function (cl) { return S().figures(cl, lines || null, r); });
    });
  }
  function sixMonths() {
    var ms = CH.months(6);
    return { from: ms[0].start, to: new Date() };
  }
  function moneyWord(by) {
    var M = window.ADspaceMoney;
    var keys = Object.keys(by || {}).filter(function (k) { return by[k]; });
    if (!keys.length) return M ? M.money(0, 'MY', 2) : '0.00';
    return keys.sort().map(function (k) { return M ? M.money2(by[k], k) : by[k].toFixed(2); }).join(' · ');
  }
  var canLeads = function () { return may('clients', 'manage') && may('clients.leads', 'work'); };
  var canClients = function () { return may('clients', 'manage'); };
  var canTeamWork = function () { return may('ops.all') && may('ops.reports'); };
  var canFigures = function () { return may('ops.reports'); };
  var canReports = function () { return may('reports', 'manage'); };
  var canCamps = function () { return may('campaigns.campaigns', 'manage'); };
  var canSets = function () { return may('review.sets', 'manage'); };
  var canRequests = function () { return may('clients.requests', 'manage'); };
  var canValue = function () { return may('clients.services', 'view'); };

  /* ---- Needs attention: one list of everything waiting -------------------------
     Each source asks its own permission, reads through the shared reads and
     answers rows `{ name, meta, tag, who, late, days, since, tone, url,
     section }`. Late rows come first, the most days late first; then what
     waits on somebody, the longest first; then what has not started. */
  var STAGE_WORD = { none: 'Not started', draft: 'Draft', confirmed: 'Confirmed', review: 'In review' };
  function taskName(t) { return t.title || ('#WT' + String(t.task_no || '').padStart(5, '0')); }
  function overWord(t) {
    return (t.over_minutes != null && (Number(t.days_over) || 0) < 1
      ? (Number(t.over_minutes) < 60 ? Math.max(1, Number(t.over_minutes)) + 'm' : Math.floor(Number(t.over_minutes) / 60) + 'h')
      : daysWord(Number(t.days_over) || 0)) + ' late';
  }
  function reportLateDays(x) { return Math.max(1, Math.floor((Date.now() - new Date(x.due).getTime()) / 86400000)); }
  var SOURCES = [
    { key: 'late', word: 'Late', title: 'Late tasks', can: canFigures, load: function () {
      return R.report().then(function (d) {
        return (d.late || []).map(function (t) {
          return { name: taskName(t), meta: t.client || 'Internal', tag: 'Task', who: t.owner || 'Unassigned', client: t.client_id, clientName: t.client,
                   late: true, days: Number(t.days_over) || 0, since: overWord(t), taskId: t.task_id, src: 'late',
                   url: '/admin/?s=work&open=' + encodeURIComponent(t.task_id), section: 'work' };
        });
      });
    } },
    /* A client paused or ended still owes its revisions and reviews. */
    { key: 'urgent', word: 'Urgent delivery', title: 'Open work for paused and past clients', can: function () { return may('ops', 'manage') && may('ops.all'); }, load: function () {
      return R.openTasks().then(function (list) {
        return list.filter(function (t) { var st = t.clients && t.clients.stage; return st === 'paused' || st === 'past'; }).map(function (t) {
          var n = t.current_final_due_at ? CK.between(CK.day(t.current_final_due_at), CK.today()) : null;
          return { name: taskName(t), meta: [t.clients.name, 'Urgent delivery'].join(' · '), tag: 'Task', who: '', client: t.client_id,
                   late: n > 0, days: n > 0 ? n : 0, since: n === null ? 'No due date' : n > 0 ? daysWord(n) + ' late' : 'Due ' + dateWord(t.current_final_due_at),
                   tone: n > 0 ? '' : 'warn', taskId: t.id, src: 'urgent', url: '/admin/?s=work&open=' + encodeURIComponent(t.id), section: 'work' };
        });
      });
    } },
    { key: 'owed', word: 'Reports owed', title: function () { return 'Reports for ' + lastMonth().word; }, can: canReports, load: function () {
      var SM = window.ADspaceSmReport;
      return R.owed().then(function (items) {
        return items.filter(function (x) { return x.status !== 'published' && x.status !== 'review'; }).map(function (x) {
          var c = { slug: x.slug, id: x.client_id };
          return { name: (SM && SM.titleOf ? SM.titleOf({ kind: x.kind }) : x.kind) + ', ' + lastMonth().short,
                   meta: [x.brand || x.client, STAGE_WORD[x.status] || x.status].filter(Boolean).join(' · '), tag: 'Report', client: x.client_id,
                   who: x.assignee || '', late: Boolean(x.late), days: x.late ? reportLateDays(x) : 0,
                   since: x.late ? daysWord(reportLateDays(x)) + ' late' : 'Due ' + dateWord(x.due), tone: x.late ? '' : 'off',
                   taskId: x.task_id || null, src: 'owed',
                   url: x.report_id ? '/admin/?s=reports&report=' + encodeURIComponent(x.report_id)
                     : x.task_id && may('ops') ? '/admin/?s=work&open=' + encodeURIComponent(x.task_id)
                     : may('clients') ? clientUrl(c, 'engagements') : '/admin/?s=reports',
                   section: x.report_id ? 'reports' : x.task_id && may('ops') ? 'work' : may('clients') ? 'clients' : 'reports' };
        });
      });
    } },
    { key: 'confirm', word: 'To confirm', title: 'Reports waiting for confirmation', can: canReports, load: function () {
      var SM = window.ADspaceSmReport;
      return R.inReview().then(function (list) {
        return list.map(function (r) {
          return { name: SM && SM.titleOf ? SM.titleOf(r) : r.title,
                   meta: [(r.clients && r.clients.name) || 'Client', 'In review'].join(' · '), tag: 'Report', client: r.client_id,
                   who: (r.clients && r.clients.owner) || '', days: daysSince(r.submitted_at), since: sinceWord(r.submitted_at), tone: 'warn',
                   url: '/admin/?s=reports&report=' + encodeURIComponent(r.id), section: 'reports' };
        });
      });
    } },
    { key: 'cold', word: 'Cold leads', title: 'Leads going cold', can: canLeads, load: function () {
      /* The Clients list's own rule, so the two agree at the boundary
         (2026-10-22, OVW-7). */
      var CRM = window.ADspaceCRM;
      return R.clients().then(function (list) {
        var now = Date.now();
        return list.filter(function (c) { return c.stage === 'lead' || c.stage === 'proposal'; }).map(function (c) {
          return { c: Object.assign({}, c, { stage_since: c.stage_since || c.created_at }), h: (now - new Date(c.stage_since || c.created_at).getTime()) / 3600000 };
        }).filter(function (x) { return CRM.isStale(x.c); }).map(function (x) {
          var c = x.c, d = Math.floor(x.h / 24);
          return { name: c.name, meta: [(W.stage || {})[c.stage] || c.stage, 'Overdue'].join(' · '), tag: 'Lead', who: c.owner || '', client: c.id,
                   late: true, days: d, since: daysWord(d), url: clientUrl(c), section: 'clients' };
        });
      });
    } },
    { key: 'restricted', word: 'Restricted', title: 'Restricted accounts', can: canClients, load: function () {
      return R.clients().then(function (list) {
        return list.filter(function (c) { return c.restricted_since; }).map(function (c) {
          return { name: c.name, meta: [RESTRICT_WORD[c.restricted_platform] || 'Account', 'Restricted', c.restricted_note].filter(Boolean).join(' · '),
                   tag: 'Client', who: c.owner || '', client: c.id, late: true, days: daysSince(c.restricted_since), since: sinceWord(c.restricted_since),
                   url: clientUrl(c), section: 'clients' };
        });
      });
    } },
    { key: 'requests', word: 'Requests', title: 'Unanswered requests', can: canRequests, load: function () {
      return R.requests().then(function (list) {
        return list.map(function (q) {
          var c = q.clients || {};
          return { name: [(W.rqKind || {})[q.kind] || q.kind, q.service_label].filter(Boolean).join(': '),
                   meta: [c.name || 'Client', (W.rqState || {})[q.state] || q.state].join(' · '), tag: 'Request', who: c.owner || '', client: q.client_id,
                   days: daysSince(q.created_at), since: sinceWord(q.created_at), tone: 'warn', url: clientUrl(c, 'services'), section: 'clients' };
        });
      });
    } },
    { key: 'sets', word: 'Sets waiting', title: 'Sets waiting on the client', can: canSets, load: function () {
      return R.sets().then(function (list) {
        return list.map(function (x) {
          var c = x.s.clients || {};
          return { name: x.s.title, meta: [c.name || 'Client', x.ok + ' of ' + x.n + ' approved', x.ch ? x.ch + ' changes requested' : ''].filter(Boolean).join(' · '),
                   tag: 'Content Review', who: c.owner || '', client: c.id || x.s.client_id, days: daysSince(x.s.published_at || x.s.created_at),
                   since: sinceWord(x.s.published_at || x.s.created_at), tone: 'warn',
                   url: '/admin/?s=review&client=' + encodeURIComponent(c.id || x.s.client_id) + '&set=' + encodeURIComponent(x.s.id), section: 'review' };
        });
      });
    } },
    { key: 'noset', word: 'No set', title: 'No set this month', can: canSets, load: function () {
      return R.noSet().then(function (list) {
        return list.map(function (x) {
          return { name: x.c.name, meta: 'No set this month' + (x.last ? ' · Last set ' + dateWord(x.last) : ''), tag: 'Content Review',
                   who: x.c.owner || '', client: x.c.id, days: 0, since: 'Not started', tone: 'off',
                   url: '/admin/?s=review&client=' + encodeURIComponent(x.c.id), section: 'review' };
        });
      });
    } },
    { key: 'bookings', word: 'Bookings', title: 'Bookings past their date', can: canCamps, load: function () {
      var t0 = isoDay(today());
      return R.bookings().then(function (list) {
        return list.filter(function (o) { return o.state === 'pending_visit' || o.state === 'pending_draft' || o.state === 'changes'; }).map(function (o) {
          return { o: o, due: o.state === 'pending_visit' ? o.visit_date : o.submission_due };
        }).filter(function (x) { return x.due && String(x.due).slice(0, 10) < t0; }).map(function (x) {
          var o = x.o, cp = o.campaigns || {};
          return { name: (o.creators && o.creators.name) || 'Creator',
                   meta: [cp.title, o.state === 'pending_visit' ? 'Visit ' + dateWord(x.due) : 'Draft due ' + dateWord(x.due)].filter(Boolean).join(' · '),
                   tag: 'Campaign', who: cp.owner || '', client: cp.client_id, late: true, days: daysSince(x.due), since: daysWord(daysSince(x.due)) + ' late',
                   url: '/admin/?s=campaigns&campaign=' + encodeURIComponent(o.campaign_id) + '&pane=schedule', section: 'campaigns' };
        });
      });
    } },
    { key: 'qc', word: 'Quality check', title: 'Waiting for the quality check', can: canCamps, load: function () {
      return R.bookings().then(function (list) {
        return list.filter(function (o) { return o.state === 'submitted'; }).map(function (o) {
          var cp = o.campaigns || {};
          return { name: (o.creators && o.creators.name) || 'Creator', meta: [cp.title, (W.step || {}).submitted || 'Submitted'].filter(Boolean).join(' · '),
                   tag: 'Campaign', who: cp.owner || '', client: cp.client_id, days: daysSince(o.submitted_at), since: sinceWord(o.submitted_at), tone: 'warn',
                   url: '/admin/?s=campaigns&campaign=' + encodeURIComponent(o.campaign_id) + '&pane=creators', section: 'campaigns' };
        });
      });
    } },
    { key: 'checklists', word: 'Checklists', title: 'Client checklists not signed off', can: function () { return may('clients.checklists', 'manage'); }, load: function () {
      return db.rpc('client_checklists_due').then(rows).then(function (list) {
        return (list || []).map(function (c) {
          var what = c.kind === 'pre_ads' ? 'Pre-Advertising Checklist' : 'New Client Onboarding Checklist';
          var st = c.status === 'prepared' ? 'Waiting for sign-off' : c.started ? 'In progress' : 'Not started';
          return { name: what, meta: [c.name, st].join(' · '), tag: 'Client', who: c.owner || '', client: c.client_id,
                   days: daysSince(c.since), since: sinceWord(c.since), tone: c.started ? 'warn' : 'off',
                   url: clientUrl({ slug: c.slug, id: c.client_id }, 'checklists') + '&list=' + c.kind, section: 'clients' };
        });
      });
    } },
    { key: 'unsigned', word: 'Unsigned letters', title: 'Letters of Offer not yet signed', can: function () { return may('clients.documents', 'manage'); }, load: function () {
      return R.letters().then(function (list) {
        return list.map(function (d) {
          var c = d.clients || {};
          return { name: d.number, meta: [c.name || 'Client', 'Issued ' + dateWord(d.issued_at)].join(' · '), tag: 'Document', who: c.owner || '', client: c.id || d.client_id,
                   days: daysSince(d.issued_at), since: daysWord(daysSince(d.issued_at)), tone: 'warn', url: clientUrl(c, 'documents'), section: 'clients' };
        });
      });
    } },
    { key: 'reviews', word: 'Reviews', title: function () { return 'Reviews for ' + lastMonth().word; }, can: function () { return may('team.performance'); }, load: function () {
      var P = window.ADspacePerf, words = (P && P.status) || {};
      return R.reviews().then(function (list) {
        return list.filter(function (r) { return r.status !== 'final'; }).map(function (r) {
          var w = words[r.status] || [r.status === 'none' ? 'Not started' : r.status, ''];
          return { name: 'Performance review, ' + lastMonth().short, meta: w[0], tag: 'Performance', who: r.name, days: 0,
                   since: w[0], tone: r.status === 'none' ? 'off' : 'warn',
                   url: '/admin/?s=team&tab=performance&m=' + lastMonth().key, section: 'team' };
        });
      });
    } }
  ];
  function rank(r) { return r.late ? 0 : r.tone === 'off' ? 2 : 1; }
  /* A VIC client's row (2026-10-15): by its client's id, else (the late
     tasks, which name their client alone) by its name. */
  function vicOfRow(r) {
    var A = window.ADspaceAdmin;
    if (!A || !A.vic) return null;
    return A.vic(r.client) || (r.clientName && A.vicByName ? A.vic(A.vicByName(r.clientName)) : null);
  }
  function attention() {
    var live = SOURCES.filter(function (s) { return s.can(); });
    return Promise.all(live.map(function (s) {
      return s.load().then(function (rs) { return { rows: rs }; }).catch(function (e) {
        return { failed: typeof s.title === 'function' ? s.title() : s.title, why: (e && e.message) || 'The read failed.' };
      });
    })).then(function (all) {
      var out = [], failed = [];
      all.forEach(function (a, i) {
        if (a.failed) { failed.push(a); return; }
        a.rows.forEach(function (r) { r.src = r.src || live[i].key; });
        out = out.concat(a.rows);
      });
      /* One row a piece of work (2026-10-22, OVW-3): a late report task is
         the owed report's row, and a late task of a paused or past client
         keeps its late row, which names Urgent delivery. */
      var owedTask = {}, lateRow = {};
      out.forEach(function (r) { if (r.src === 'owed' && r.taskId) owedTask[r.taskId] = 1; });
      out = out.filter(function (r) { return !(r.src === 'late' && owedTask[r.taskId]); });
      out.forEach(function (r) { if (r.src === 'late' && r.taskId) lateRow[r.taskId] = r; });
      out = out.filter(function (r) {
        if (r.src !== 'urgent' || !lateRow[r.taskId]) return true;
        lateRow[r.taskId].meta += ' · Urgent delivery';
        return false;
      });
      out.forEach(function (r) { var v = vicOfRow(r); r.vic = v ? v.client_id : ''; });
      /* VIC first among equals: late before waiting before not started, then VIC. */
      out.sort(function (a, b) { return rank(a) - rank(b) || (a.vic ? 0 : 1) - (b.vic ? 0 : 1) || b.days - a.days || String(a.name).localeCompare(String(b.name)); });
      return { rows: out, failed: failed };
    });
  }

  function titleOf(x) { return typeof x.title === 'function' ? x.title() : x.title; }
  /* A tile's label, with its narrow word where it has one. */
  function label(el, t) {
    var l = el.querySelector('.ovw-kpi-label'), sh = t.short ? t.short() : '';
    l.classList.toggle('has-short', Boolean(sh));
    if (!sh) { l.textContent = titleOf(t); return; }
    l.innerHTML = '<span class="ovw-long">' + esc(titleOf(t)) + '</span><span class="ovw-short">' + esc(sh) + '</span>';
  }

  /* A tile counting one kind of client move: the period, its change on the
     period before and the six months' trend. */
  function kindTile(key, title, kind) {
    return { key: key, title: title, can: canLeads, load: function () {
      return Promise.all([figuresFor('now'), figuresFor('prev'), figuresFor('six')]).then(function (f) {
        return { fig: String(f[0][kind].length), sub: delta(f[0][kind].length, f[1][kind].length),
                 spark: f[2].months.map(function (m) { return m[kind]; }) };
      });
    } };
  }
  /* ---- The tiles -------------------------------------------------------------------
     A tile: its label, its figure, one line under it and, where the figure
     has a history, its trend. `load()` answers `{ fig, sub, tone, spark,
     bar }`. */
  var SALES = [
    kindTile('leads', 'New leads', 'newLeads'),
    kindTile('won', 'Won', 'won'),
    kindTile('churned', 'Churned', 'churned'),
    /* Committed monthly value for whoever may open a client's Services, from
       the lines that part opens; Active clients for everyone else. */
    { key: 'value', title: function () { return canValue() ? 'Committed monthly value' : 'Active clients'; },
      /* Its narrow word: the whole label is cut at a phone's tile (2026-10-15, audit OVW-1). */
      short: function () { return canValue() ? 'Committed value' : ''; }, can: canClients, load: function () {
      if (canValue()) {
        return R.lines().then(function (lines) { return figuresFor('now', lines); }).then(function (f) {
          var won = f.money && f.money.won, any = won && Object.keys(won).some(function (k) { return won[k]; });
          return { fig: moneyWord(f.money && f.money.active), money: true,
                   sub: any ? moneyWord(won) + ' won ' + periodName(period) : 'None won ' + periodName(period) };
        });
      }
      return Promise.all([figuresFor('now'), figuresFor('six')]).then(function (f) {
        return { fig: String(f[0].activeEnd), sub: delta(f[0].activeEnd, f[0].activeStart),
                 spark: f[1].months.map(function (m) { return m.active; }) };
      });
    } }
  ];
  function completed(d) {
    return (d && Array.isArray(d.by_person) ? d.by_person : []).reduce(function (a, p) { return a + (Number(p.completed) || 0); }, 0);
  }
  var OPS = [
    { key: 'open', title: 'Open tasks', can: canTeamWork, load: function () {
      return R.report().then(function (d) {
        if (!Array.isArray(d.open_by_person)) throw new Error('This needs a database update.');
        var people = d.open_by_person.filter(function (p) { return Number(p.open) > 0; });
        var n = people.reduce(function (a, p) { return a + (Number(p.open) || 0); }, 0);
        return { fig: String(n), sub: people.length === 1 ? 'With 1 person' : 'Across ' + people.length + ' people' };
      });
    } },
    /* The count is the Late tasks signal's; the tile states how late the
       oldest is, so nothing on the page is said twice (2026-10-22, OVW-5). */
    { key: 'late', title: 'Oldest late', can: canFigures, load: function () {
      return R.report().then(function (d) {
        var l = d.late || [], top = l.reduce(function (a, t) { return Math.max(a, Number(t.days_over) || 0); }, 0);
        return { fig: l.length ? daysWord(top) : 'None', tone: l.length ? 'err' : '', sub: '' };
      });
    } },
    { key: 'delivered', title: function () { return 'Delivered ' + periodName(period); }, can: canFigures, load: function () {
      return Promise.all([R.report(), R.reportPrev(), R.months()]).then(function (r) {
        var n = completed(r[0]);
        return { fig: String(n), sub: delta(n, completed(r[1])), spark: r[2].map(function (x) { return completed(x.d); }) };
      });
    } },
    { key: 'published', title: function () { return 'Reports published, ' + lastMonth().short; }, can: canReports, load: function () {
      return R.owed().then(function (items) {
        var done = items.filter(function (x) { return x.status === 'published'; }).length;
        var open = items.filter(function (x) { return x.status !== 'published'; });
        var due = open.map(function (x) { return x.due; }).filter(Boolean).sort()[0];
        return { fig: done + ' of ' + items.length, bar: items.length ? done / items.length : 0,
                 sub: !items.length ? 'None owed' : open.length ? open.length + ' owed' + (due ? ' · due ' + shortDate(due) : '') : 'All published' };
      });
    } }
  ];

  // Minutes as a person reads them: "45m", "6.5h", "3.2 days".
  function spanOf(m) {
    m = Number(m) || 0;
    if (m < 60) return Math.round(m) + 'm';
    if (m < 1440) return String(Math.round(m / 6) / 10).replace(/\.0$/, '') + 'h';
    var d = Math.round(m / 144) / 10;
    return String(d).replace(/\.0$/, '') + (d === 1 ? ' day' : ' days');
  }

  /* ---- The charts ------------------------------------------------------------------
     Each answers a spec for ADspaceChart.draw, or `{ empty }`. */
  /* The Dashboard in two pages (the user, 2026-10-12: "act as the company
     ceo"): Summary, what a director reads first, and Detail, the same
     period read further, a page of its own reached from the strip and from
     the foot of the Summary, never folded away as if it mattered less. Each
     row is a grid of cards; the second row of Detail runs three across. */
  var PAGE1 = [
    [
      /* Delivery (the team's: client review by its due date) and posting
         (the client's: live by its post date) side by side (the user,
         2026-10-19: "Build posted on time on the dashboard"). */
      { key: 'ontime', title: 'On time by month', can: canFigures, all: ['My Work', '/admin/?s=work', 'work'], load: function () {
        return R.months().then(function (all) {
          var rate = function (met, n) { return n ? Math.round(met / n * 100) : null; };
          var cats = all.map(function (x) {
            var f = x.d.on_time || {}, n = Number(f.reached || 0) + Number(f.late_open || 0), met = Number(f.met || 0);
            var p = x.d.posted || {}, pn = Number(p.due || 0), pm = Number(p.met || 0);
            return { label: x.m.label, long: x.m.long, values: [rate(met, n), rate(pm, pn)], n: n, met: met, pn: pn, pm: pm };
          });
          if (!cats.some(function (c) { return c.values[0] != null || c.values[1] != null; })) return { empty: 'No tasks or posts were due in the last six months.' };
          var cell = function (met, n, v) { return v == null ? '\u2014' : v + '% (' + met + ' of ' + n + ')'; };
          return { kind: 'line', max: 100, none: 'None due', cats: cats,
            series: [{ label: 'Delivered on time' }, { label: 'Posted on time', tone: 'mute' }],
            fmt: function (v) { return Math.round(Number(v) || 0) + '%'; },
            table: { heads: ['Month', 'Delivered on time', 'Posted on time'], rows: cats.map(function (c) {
              return [c.long, cell(c.met, c.n, c.values[0]), cell(c.pm, c.pn, c.values[1])];
            }) } };
        });
      } },
      { key: 'active', title: 'Active clients by month', can: canClients,
        all: function () { return ['Clients', '/admin/?s=clients', 'clients']; }, load: function () {
        return figuresFor('six').then(function (f) {
          if (!f.months.some(function (m) { return m.active; })) return { empty: 'No active clients in the last six months.' };
          var last = f.months.length - 1;
          /* The month still running is drawn lighter: its figure is so far. */
          return { kind: 'columns', labels: true, cats: f.months.map(function (m, i) { return { label: m.label, long: m.long, values: [m.active], tone: i === last ? 'mute' : '' }; }),
                   series: [{ label: 'Active clients' }] };
        });
      } }
    ]
  ];
  var PAGE2 = [
    ['Sales', [
      [
      { key: 'funnel', title: 'Leads to clients', can: canLeads,
        all: ['Clients', '/admin/?s=clients', 'clients'], load: function () {
        return figuresFor('now').then(function (f) {
          /* Each step counts this period's new leads alone (2026-10-20, OVW-5). */
          var words = ['New leads', 'Contacted', 'Proposal sent', 'New leads now clients'];
          var n = f.funnel.map(function (l) { return l.length; });
          if (!n[0]) return { empty: 'No new leads ' + periodName(period) + '.' };
          return { kind: 'bars', inline: true, rows: words.map(function (w, i) {
            return { label: w, value: n[i], note: i ? (n[i - 1] ? Math.round(n[i] / n[i - 1] * 100) + '%' : '0%') : '' };
          }), table: { heads: ['Step', 'Leads', 'Of the step before'], rows: words.map(function (w, i) {
            return [w, String(n[i]), i ? (n[i - 1] ? Math.round(n[i] / n[i - 1] * 100) + '%' : '—') : '—'];
          }) } };
        });
      } },
      { key: 'pipeline', title: 'Pipeline now', can: canLeads, all: ['Clients', '/admin/?s=clients', 'clients'], load: function () {
        return figuresFor('now').then(function (f) {
          var p = f.pipeline;
          if (!p.lead.length && !p.contacted.length && !p.proposal.length) return { empty: 'No open leads.' };
          return { kind: 'pie', total: true, rows: [{ label: 'Lead', value: p.lead.length }, { label: 'Contacted', value: p.contacted.length },
                                       { label: 'Proposal sent', value: p.proposal.length }] };
        });
      } }
      ],
      [
      /* What else moved in the period, from Clients · Sales (2026-10-12): the
         leads lost, the clients paused, resumed and won back, how long a lead
         takes to win, conversion and churn, and for whoever may open client
         Services the value won and lost. */
      { key: 'moves', title: 'Sales moves', can: canLeads,
        all: ['Clients', '/admin/?s=clients', 'clients'], load: function () {
        var val = canValue();
        return (val ? R.lines() : Promise.resolve(null)).then(function (lines) { return figuresFor('now', lines); }).then(function (f) {
          var pct = function (a, b) { return b ? Math.round(a / b * 100) + '%' : '—'; };
          var decided = f.won.length + f.lost.length;
          var rowsOf = [
            ['Lost leads', String(f.lost.length), 'Past before ever Active'],
            ['Paused', String(f.paused.length), f.pausedNow.length + ' paused now'],
            ['Resumed', String(f.resumed.length), 'Paused back to Active'],
            ['Win-backs', String(f.winback.length), 'Past back to Active'],
            ['Lead to won', f.medianToWin === null ? '—' : daysWord(f.medianToWin), 'Median'],
            ['Conversion', pct(f.won.length, decided), 'Won of the leads decided'],
            ['Churn rate', pct(f.churned.length, f.activeStart), 'Churned of those active at the start', true]
          ];
          if (val && f.money) {
            rowsOf.push(['Monthly value won', moneyWord(f.money.won), 'A month of the lines won', true]);
            rowsOf.push(['Monthly value lost', moneyWord(f.money.churned), 'A month of the lines churned', true]);
          }
          return { html: '<dl class="ovw-facts">' + rowsOf.map(function (r) {
            /* Churn and the two values take a row each, so a long label
               or an amount never squeezes into half (the user, 2026-10-12). */
            return '<div' + (r[3] ? ' class="is-wide"' : '') + '><dt>' + esc(r[0]) + '<small>' + esc(r[2]) + '</small></dt><dd>' + esc(r[1]) + '</dd></div>';
          }).join('') + '</dl>' };
        });
      } },
      /* Who brought the leads in and who kept the clients (from Clients ·
         Sales, 2026-10-12): counts only, never a ranking. */
      { key: 'owners', title: 'By person in charge', can: canLeads,
        all: ['Clients', '/admin/?s=clients', 'clients'], load: function () {
        return figuresFor('now').then(function (f) {
          var ppl = Object.keys(f.byPerson).sort(function (a, b) { return a.localeCompare(b); }).map(function (k) { return f.byPerson[k]; })
            .filter(function (q) { return q.newLeads.length || q.won.length || q.lost.length || q.churned.length; });
          if (!ppl.length) return { empty: 'Nothing moved ' + periodName(period) + '.' };
          return { html: '<div class="chart-tblwrap"><table class="chart-tbl ovw-tbl"><thead><tr><th scope="col">Person in charge</th>' +
            '<th scope="col" class="is-end">New leads</th><th scope="col" class="is-end">Won</th><th scope="col" class="is-end">Lost</th><th scope="col" class="is-end">Churned</th></tr></thead><tbody>' +
            ppl.map(function (q) {
              return '<tr><th scope="row">' + esc(q.name) + '</th><td class="is-end">' + q.newLeads.length + '</td><td class="is-end">' + q.won.length +
                '</td><td class="is-end">' + q.lost.length + '</td><td class="is-end">' + q.churned.length + '</td></tr>';
            }).join('') + '</tbody></table></div>' };
        });
      } }
      ],
      [
      { key: 'sources', title: 'New leads by source', can: canLeads,
        all: ['Clients', '/admin/?s=clients', 'clients'], load: function () {
        return figuresFor('now').then(function (f) {
          var rowsOf = Object.keys(f.bySource).map(function (k) { return { label: k, value: f.bySource[k].length }; })
            .sort(function (a, b) { return b.value - a.value || a.label.localeCompare(b.label); });
          if (!rowsOf.length) return { empty: 'No new leads ' + periodName(period) + '.' };
          return { kind: 'bars', inline: true, rows: rowsOf, valueHead: 'New leads' };
        });
      } },
      { key: 'reasons', title: 'Why clients paused or left', can: canClients,
        all: function () { return ['Clients', '/admin/?s=clients', 'clients']; },
        load: function () {
        return figuresFor('now').then(function (f) {
          var word = S().reasonWord || function (k) { return k || 'Not given'; };
          var rowsOf = Object.keys(f.reasons).map(function (k) {
            var r = f.reasons[k], pa = r.paused.length, le = r.past.length;
            return { label: word(k), value: pa + le, note: [pa ? pa + ' paused' : '', le ? le + ' left' : ''].filter(Boolean).join(' · ') };
          }).sort(function (a, b) { return b.value - a.value; });
          if (!rowsOf.length) return { empty: 'No client paused or left ' + periodName(period) + '.' };
          return { kind: 'bars', inline: true, rows: rowsOf, valueHead: 'Clients' };
        });
      } }
      ]
    ]],
    ['Operations', [
      [
      { key: 'load', title: 'Open work by person', can: canTeamWork, all: ['My Work', '/admin/?s=work', 'work'], load: function () {
        return R.report().then(function (d) {
          if (!Array.isArray(d.open_by_person)) throw new Error('This needs a database update.');
          /* Work nobody holds reads Unassigned, as the list on Summary says it
             (ux-audit OVW-5, 2026-10-15); the database names it otherwise. */
          var list = d.open_by_person.filter(function (r) { return Number(r.open) > 0; })
            .map(function (r) { if (!r.team_member_id) r.name = 'Unassigned'; return r; });
          if (!list.length) return { empty: 'No open tasks.' };
          return { kind: 'bars', inline: true, rows: list.map(function (r) {
              var late = Number(r.late) || 0;
              return { label: r.name, value: Number(r.open) || 0, part: late, note: late ? late + ' late' : '', noteTone: late ? 'err' : '' };
            }),
            fmt: function (v) { return String(v); },
            table: { heads: ['Assigned to', 'Open', 'Late'], rows: list.map(function (r) { return [r.name, String(r.open), String(r.late || 0)]; }) } };
        });
      } },
      { key: 'waits', title: 'Where work waits', can: canFigures,
        all: ['My Work', '/admin/?s=work', 'work'], load: function () {
        return R.report().then(function (d) {
          /* Each stage's open work beside its time (the Report's Open work by
             stage, 2026-10-12). */
          var openAt = {};
          (d.running || []).forEach(function (r) { openAt[r.stage_key] = Number(r.count) || 0; });
          var st = (d.stage_time || []).filter(function (x) { return Number(x.n) > 0; })
            .sort(function (a, b) { return (Number(b.median_minutes) || 0) - (Number(a.median_minutes) || 0); }).slice(0, 6);
          if (!st.length) return { empty: 'No task left a stage ' + periodName(period) + '.' };
          return { kind: 'bars', markLabel: 'Slowest 10%', rows: st.map(function (x) {
              return { label: x.label || x.stage_key, value: Number(x.median_minutes) || 0, mark: Number(x.p90_minutes) || 0,
                       note: (openAt[x.stage_key] || 0) + ' open' };
            }), fmt: function (v) { return spanOf(v); },
            table: { heads: ['Stage', 'Open now', 'Times left', 'Median', 'Slowest 10%'], rows: st.map(function (x) {
              return [x.label || x.stage_key, String(openAt[x.stage_key] || 0), String(x.n), spanOf(x.median_minutes), spanOf(x.p90_minutes)];
            }) } };
        });
      } }
      ],
      [
      { key: 'ontimeby', title: 'On time by person', can: canFigures,
        all: ['My Work', '/admin/?s=work', 'work'], load: function () {
        return R.report().then(function (d) {
          var by = (d.by_person || []).filter(function (x) { return Number(x.completed) > 0; })
            .sort(function (a, b) { return (Number(b.completed) || 0) - (Number(a.completed) || 0); });
          if (!by.length) return { empty: 'Nothing was delivered ' + periodName(period) + '.' };
          var pc = function (x) { return Math.round((Number(x.on_time) || 0) / Number(x.completed) * 100); };
          return { kind: 'bars', inline: true, rows: by.map(function (x) {
              return { label: x.name, value: Number(x.completed) || 0, part: Math.max(0, Number(x.completed) - (Number(x.on_time) || 0)),
                       note: pc(x) + '% on time' + (x.median_cycle_minutes ? ' · ' + spanOf(x.median_cycle_minutes) : '') };
            }), fmt: function (v) { return String(v); },
            table: { heads: ['Person', 'Delivered', 'On time', 'Rate', 'Median cycle'], rows: by.map(function (x) {
              return [x.name, String(x.completed), String(x.on_time || 0), pc(x) + '%', x.median_cycle_minutes ? spanOf(x.median_cycle_minutes) : '\u2014'];
            }) } };
        });
      } },
      { key: 'reports', title: function () { return 'Reports for ' + LONG[lastMonth().mo]; }, can: canReports, all: ['Reports', '/admin/?s=reports', 'reports'], load: function () {
        return R.owed().then(function (items) {
          if (!items.length) return { empty: 'No reports owed.' };
          var n = function (st) { return items.filter(function (x) { return x.status === st; }).length; };
          var lateNone = items.some(function (x) { return x.status === 'none' && x.late; });
          return { kind: 'pie', total: true, rows: [{ label: 'Published', value: n('published'), tone: 'ok' }, { label: 'In review', value: n('review'), tone: 'warn' },
            { label: 'Confirmed', value: n('confirmed'), tone: 'warn' }, { label: 'Draft', value: n('draft'), tone: 'off' },
            { label: 'Not started', value: n('none'), tone: lateNone ? 'err' : 'off' }] };
        });
      } },
      { key: 'bookings', title: 'Creator bookings', can: canCamps, all: ['Creator Campaigns', '/admin/?s=campaigns', 'campaigns'], load: function () {
        return R.bookings().then(function (list) {
          var n = function (sts) { return list.filter(function (o) { return sts.indexOf(o.state) > -1; }).length; };
          if (!list.length) return { empty: 'No open bookings.' };
          return { kind: 'bars', inline: true, rows: [{ label: 'To shoot', value: n(['pending_visit']) }, { label: 'Draft owed', value: n(['pending_draft', 'changes']) },
            { label: 'Quality check', value: n(['submitted']) }, { label: 'With client', value: n(['reviewing']) },
            { label: 'To post', value: n(['scheduled']) }], valueHead: 'Bookings' };
        });
      } }
      ]
    ]]
  ];
  var CHARTS = PAGE1.concat(PAGE2[0][1], PAGE2[1][1]);

  /* Whether anything is allowed: the console offers the Dashboard only then
     (admin.js `sectionAllowed`), so a group with nothing to oversee here
     starts on its first route instead of an empty page. */
  var ALL = [].concat(SOURCES, SALES, OPS, [].concat.apply([], CHARTS));
  function any() { return ALL.some(function (c) { return c.can(); }); }

  // ---- Drawing ----------------------------------------------------------------------
  function fail(body, title, e, again) {
    UI.failLine(body, title || 'This card', (e && e.message) || 'The read failed.', again);
  }
  function glance(box) {
    /* The rings alone (2026-10-22, OVW-M1): what needs acting on today is
       the list under them, its sources counted in its own strip. */
    var meter = canFigures();
    if (!meter) return;
    var card = document.createElement('section');
    card.className = 'chartcard ovw-glance is-plain';
    card.id = 'ovwGlance';
    card.innerHTML = '<div class="ovw-meters"><div class="ovw-meter" id="ovwMeter"></div><div class="ovw-meter" id="ovwPosted"></div></div>';
    box.appendChild(card);
    if (meter) {
      var mbox = card.querySelector('#ovwMeter'), pbox = card.querySelector('#ovwPosted');
      var runM = function () {
        UI.skeleton(mbox, 2);
        UI.skeleton(pbox, 2);
        R.report().then(function (d) {
          /* Work still late counts as late beside what reached client review
             (the user, 2026-10-19: late tasks beside 100% on time). */
          var f = d.on_time || {}, n = Number(f.reached || 0) + Number(f.late_open || 0), met = Number(f.met || 0);
          /* Posted on time: content live by its post date (2026-10-19). */
          var p = d.posted || {}, pn = Number(p.due || 0), pm = Number(p.met || 0);
          mbox.innerHTML = '';
          pbox.innerHTML = '';
          /* The rings stand whatever the period holds (the user, 2026-10-12):
             with nothing due they are empty and read a dash. */
          CH.draw(mbox, { kind: 'meter', name: 'On-time delivery', word: 'On-time delivery', valueHead: 'Tasks',
            rows: [{ label: 'On time', value: met, tone: 'ok' }, { label: 'Late', value: n - met }] });
          CH.draw(pbox, { kind: 'meter', name: 'Posted on time', word: 'Posted on time', valueHead: 'Posts',
            rows: [{ label: 'On time', value: pm, tone: 'ok' }, { label: 'Late', value: pn - pm }] });
        }).catch(function (e) { fail(mbox, 'On-time delivery', e, runM); pbox.innerHTML = ''; });
      };
      runM();
    }
  }
  function tile(grid, t) {
    var el = document.createElement('article');
    el.className = 'chartcard ovw-kpi';
    el.setAttribute('data-tile', t.key);
    el.innerHTML = '<span class="ovw-kpi-label"></span><b class="ovw-kpi-fig"><span class="skel skel-w"></span></b>' +
      '<span class="ovw-kpi-sub"></span><span class="ovw-kpi-trend"></span>';
    label(el, t);
    grid.appendChild(el);
    var run = function () {
      t.load().then(function (o) {
        var fig = el.querySelector('.ovw-kpi-fig');
        fig.textContent = o.fig;
        fig.className = 'ovw-kpi-fig' + (o.tone ? ' is-' + o.tone : '') + (o.money ? ' is-money' : '');
        label(el, t);
        el.querySelector('.ovw-kpi-sub').textContent = o.sub || '';
        el.querySelector('.ovw-kpi-trend').innerHTML = o.bar != null
          ? '<span class="ovw-kpi-bar" aria-hidden="true"><i style="width:' + Math.round(o.bar * 100) + '%"></i></span>'
          : (o.spark ? CH.spark(o.spark, o.tone) : '');
      }).catch(function (e) {
        el.querySelector('.ovw-kpi-fig').textContent = '—';
        el.querySelector('.ovw-kpi-sub').innerHTML = '';
        var b = document.createElement('button');
        b.type = 'button'; b.className = 'btn btn-quiet btn-sm ovw-kpi-again'; b.textContent = 'Try again';
        b.setAttribute('aria-label', 'Try again: ' + titleOf(t) + '. ' + ((e && e.message) || 'The read failed.'));
        b.addEventListener('click', function () { el.querySelector('.ovw-kpi-sub').textContent = ''; run(); });
        el.querySelector('.ovw-kpi-sub').appendChild(document.createTextNode('Could not load. '));
        el.querySelector('.ovw-kpi-sub').appendChild(b);
      });
    };
    run();
  }
  function tiles(box) {
    var groups = [['Sales', SALES, 'ovwSales'], ['Operations', OPS, 'ovwOps']].map(function (g) {
      return { head: g[0], list: g[1].filter(function (t) { return t.can(); }), id: g[2] };
    }).filter(function (g) { return g.list.length; });
    if (!groups.length) return;
    var wrap = document.createElement('div');
    wrap.className = 'ovw-groups' + (groups.length === 1 ? ' is-one' : '');
    box.appendChild(wrap);
    groups.forEach(function (g) {
      var sec = document.createElement('section');
      sec.className = 'ovw-group';
      sec.id = g.id;
      sec.innerHTML = '<h3 class="ovw-group-h"></h3><div class="ovw-kpis"></div>';
      sec.firstChild.textContent = g.head;
      wrap.appendChild(sec);
      var grid = sec.querySelector('.ovw-kpis');
      g.list.forEach(function (t) { tile(grid, t); });
    });
  }
  /* A chart's title with its way out at the right edge ("Sales ›"), the
     section it is read from. */
  function headOf(card, title, all) {
    var h = card.querySelector('.chart-title');
    if (!h) { h = document.createElement('h3'); card.insertBefore(h, card.firstChild); }
    var head = document.createElement('div');
    head.className = 'ovw-cardhead';
    var t = document.createElement('h3');
    t.textContent = title;
    head.appendChild(t);
    if (all) {
      var b = document.createElement('button');
      b.type = 'button'; b.className = 'btn btn-quiet btn-sm ovgo';
      b.innerHTML = '<span class="ovgo-word"></span>' + CHEV;
      b.firstChild.textContent = all[0];
      b.setAttribute('aria-label', all[0] + ': ' + title);
      b.addEventListener('click', function () { go(all[1], all[2]); });
      head.appendChild(b);
    }
    h.replaceWith(head);
  }
  function chart(grid, c) {
    var title = titleOf(c), all = typeof c.all === 'function' ? c.all() : c.all;
    var el = document.createElement('div');
    el.className = 'chartcard ovw-card';
    el.setAttribute('data-card', c.key);
    el.innerHTML = '<h3 class="chart-title"></h3><div class="ovw-body"></div>';
    headOf(el, title, all);
    grid.appendChild(el);
    var body = el.querySelector('.ovw-body');
    var run = function () {
      UI.skeleton(body, 3);
      Promise.resolve().then(function () { return c.load(); }).then(function (out) {
        if (!el.isConnected) return;
        /* An empty card's line stands in the middle of the room its row gives
           it (ux-audit OVW-2, 2026-10-15). */
        el.classList.toggle('is-empty', Boolean(out.empty));
        if (out.empty) { UI.emptyLine(body, out.empty); return; }
        /* A card of figures or a table rather than a chart (Sales moves, By
           person in charge) keeps its card and takes the markup. */
        if (out.html) { body.innerHTML = out.html; return; }
        out.title = title;
        var holder = document.createElement('div');
        CH.draw(holder, out);
        var drawn = holder.firstElementChild;
        if (drawn) {
          drawn.classList.add('ovw-card'); drawn.setAttribute('data-card', c.key);
          headOf(drawn, title, all);
          el.replaceWith(drawn); el = drawn;
        }
      }).catch(function (e) { if (el.isConnected) fail(body, title, e, run); });
    };
    run();
  }
  /* A page's rows of cards: two across, three where a row holds three, one
     card alone taking its row. */
  function charts(box, rows) {
    rows.forEach(function (row) {
      var live = row.filter(function (c) { return c.can(); });
      if (!live.length) return;
      var grid = document.createElement('div');
      grid.className = 'chartgrid ovw-grid' + (live.length === 3 ? ' is-three' : '');
      box.appendChild(grid);
      live.forEach(function (c) { chart(grid, c); });
    });
  }
  /* Detail: Sales, then Operations, each under its label. */
  function detail(box) {
    PAGE2.forEach(function (g) {
      if (!g[1].some(function (row) { return row.some(function (c) { return c.can(); }); })) return;
      var h = document.createElement('h3');
      h.className = 'ovw-group-h ovw-page-h';
      h.textContent = g[0];
      box.appendChild(h);
      charts(box, g[1]);
    });
  }
  var PAGES = [['summary', 'Summary'], ['detail', 'Detail']];
  var page = 'summary';
  function hasDetail() { return PAGE2.some(function (g) { return g[1].some(function (row) { return row.some(function (c) { return c.can(); }); }); }); }
  /* A page turn slides (the user, 2026-10-12: the swap "felt too fast,
     lacking the proper sliding"): the page left moves out to one side as
     the new one comes in from the other, Detail from the right and Summary
     from the left, the bar and its strip holding still. The page left is a
     still copy laid where it stood on screen, gone once the slide ends. */
  var ghostGone = null;
  function turn(to) {
    if (to === page) return;
    var box = $('ovwBody'), sec = $('sectionOverview');
    var dir = to === 'detail' ? 'next' : 'prev';
    if (ghostGone) ghostGone();
    var ghost = null;
    if (box && sec && box.firstChild) {
      sec.classList.add('is-turning');
      ghost = box.cloneNode(true);
      ghost.removeAttribute('id');
      Array.prototype.forEach.call(ghost.querySelectorAll('[id]'), function (n) { n.removeAttribute('id'); });
      ghost.classList.add('ovw-ghost');
      ghost.setAttribute('aria-hidden', 'true');
      ghost.setAttribute('inert', '');
      ghost.style.left = box.offsetLeft + 'px';
      ghost.style.width = box.offsetWidth + 'px';
      ghost.style.top = (box.offsetTop - window.scrollY) + 'px';
    }
    page = to;
    build(false);
    window.scrollTo(0, 0);
    if (ghost) {
      /* Nothing of the page left shows behind the bar, which holds still. */
      var barEl = box.querySelector('.ovw-bar');
      var under = barEl ? box.offsetTop + barEl.offsetTop + barEl.offsetHeight - parseFloat(ghost.style.top) : 0;
      if (under > 0) ghost.style.clipPath = 'inset(' + Math.round(under) + 'px 0 0 0)';
      sec.appendChild(ghost);
      ghost.classList.add('is-out-' + dir);
      box.classList.add('is-in-' + dir);
      var timer;
      ghostGone = function () {
        clearTimeout(timer);
        if (ghost.parentNode) ghost.parentNode.removeChild(ghost);
        box.classList.remove('is-in-next', 'is-in-prev');
        sec.classList.remove('is-turning');
        ghostGone = null;
      };
      ghost.addEventListener('animationend', function () { if (ghostGone) ghostGone(); });
      timer = setTimeout(function () { if (ghostGone) ghostGone(); }, 900);
    }
    if (bridge.setUrl) bridge.setUrl();
  }
  /* The way on at a page's foot: Summary continues to Detail, Detail goes
     back to Summary. */
  function foot(box) {
    if (!hasDetail()) return;
    var row = document.createElement('div');
    row.className = 'ovw-foot';
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'btn ovw-turn';
    b.id = 'ovwTurn';
    /* The pair is one act drawn one way: each carries the chevron toward
       the page it turns to (ux-audit, act glyphs, 2026-10-15). */
    b.innerHTML = page === 'summary' ? '<span>Continue to Detail</span>' + CHEV : CHEV.replace('class="ovgo-chev"', 'class="ovgo-chev is-back"') + '<span>Back to Summary</span>';
    b.addEventListener('click', function () { turn(page === 'summary' ? 'detail' : 'summary'); });
    row.appendChild(b);
    box.appendChild(row);
  }

  var SHOWN = 5;
  /* Needs attention, straight under the rings (2026-10-22, OVW-M1; the
     user's "Fix all" reopening the order approved on 2026-10-12): its head
     counts each source as the view strip, All first, a source's tab
     narrowing the list to it, red where it holds late work; five rows, then
     Show N more. */
  function list(box) {
    if (!SOURCES.some(function (s) { return s.can(); })) return;
    var card = document.createElement('section');
    card.className = 'chartcard ovw-card ovw-att';
    card.id = 'ovwAttention';
    card.innerHTML = '<div class="ovw-cardhead"><h3>Needs attention</h3><span class="ovw-count" hidden></span></div><div class="ovw-srcs-host"></div><div class="ovw-body"></div>';
    box.appendChild(card);
    var body = card.querySelector('.ovw-body'), host = card.querySelector('.ovw-srcs-host');
    var pick = '';
    var SEC_OF = { Task: 'My Work', Report: 'Reports', Lead: 'Clients', Client: 'Clients', Request: 'Clients',
      Document: 'Clients', Campaign: 'Creator Campaigns', Performance: 'Team' };
    var DOWN = '<svg class="ovw-more-chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 9l6 6 6-6"/></svg>';
    var wordOf = {};
    SOURCES.forEach(function (s) { wordOf[s.key] = s.word || titleOf(s); });
    function strip(a) {
      var counts = {}, late = {}, order = [];
      a.rows.forEach(function (r) {
        if (!counts[r.src]) { counts[r.src] = 0; order.push(r.src); }
        counts[r.src]++;
        if (r.late) late[r.src] = 1;
      });
      if (pick && !counts[pick]) pick = '';
      host.innerHTML = '';
      /* One source needs no strip: the head counts it, as the strip's All
         would (a count said once). */
      var count = card.querySelector('.ovw-count');
      count.hidden = order.length > 1 || !a.rows.length;
      count.textContent = String(a.rows.length);
      count.className = 'ovw-count tone' + (a.rows.some(function (r) { return r.late; }) ? ' is-danger' : '');
      if (order.length < 2) return;
      order.sort(function (x, y) { return SOURCES.map(function (s) { return s.key; }).indexOf(x) - SOURCES.map(function (s) { return s.key; }).indexOf(y); });
      var anyLate = a.rows.some(function (r) { return r.late; });
      var tab = function (k, word, n, red) {
        var on = k === pick;
        return '<button class="tab' + (on ? ' is-on' : '') + '" type="button" role="tab" data-src="' + k + '" aria-selected="' + on + '"' + (on ? '' : ' tabindex="-1"') + '>' +
          '<span>' + esc(word) + '</span><span class="tab-n' + (red ? ' is-err' : '') + '">' + n + '</span></button>';
      };
      host.innerHTML = '<nav class="tabrow ovw-srcs" id="ovwSrcs" role="tablist" aria-label="Needs attention by source">' +
        tab('', 'All', a.rows.length, anyLate) +
        order.map(function (k) { return tab(k, wordOf[k] || k, counts[k], late[k]); }).join('') + '</nav>';
      var nav = host.firstChild;
      if (window.ADspaceForm && window.ADspaceForm.thumb) window.ADspaceForm.thumb(nav);
      nav.addEventListener('click', function (e) {
        var t = e.target.closest && e.target.closest('.tab');
        if (!t) return;
        pick = t.getAttribute('data-src');
        Array.prototype.forEach.call(nav.querySelectorAll('.tab'), function (b) {
          var on = b === t;
          b.classList.toggle('is-on', on);
          b.setAttribute('aria-selected', String(on));
          if (on) b.removeAttribute('tabindex'); else b.setAttribute('tabindex', '-1');
        });
        if (window.ADspaceForm && window.ADspaceForm.thumb) window.ADspaceForm.thumb(nav);
        rows(a);
      });
      nav.addEventListener('keydown', function (e) {
        if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
        var tabs = Array.prototype.slice.call(nav.querySelectorAll('.tab'));
        var i = tabs.indexOf(nav.querySelector('.tab.is-on'));
        var next = tabs[(i + (e.key === 'ArrowRight' ? 1 : tabs.length - 1)) % tabs.length];
        e.preventDefault();
        next.click(); next.focus();
      });
    }
    function rows(a) {
      body.innerHTML = '';
      a.failed.forEach(function (f) {
        var h = document.createElement('div');
        body.appendChild(h);
        UI.failLine(h, f.failed, f.why, run);
      });
      if (!a.rows.length) {
        if (!a.failed.length) UI.emptyLine(body, 'Nothing waiting.');
        return;
      }
      var list = pick ? a.rows.filter(function (r) { return r.src === pick; }) : a.rows;
      /* The Section column names the rail's section, never a record's
         kind (2026-10-20, OVW-3). */
      var head = '<div class="ovw-att-head" aria-hidden="true"><span>What</span><span>Section</span><span>Who</span><span>Since</span></div>';
      var html = list.map(function (r, i) {
        var since = r.late ? '<b class="is-err">' + esc(r.since) + '</b>'
          : '<span class="chip-state tone is-' + (r.tone || 'warn') + '">' + esc(r.since) + '</span>';
        return '<button class="ovw-att-row" type="button" data-i="' + i + '"' + (i >= SHOWN ? ' hidden' : '') + '>' +
          '<span class="ovw-att-what"><b>' + esc(r.name) + (r.vic && window.ADspaceAdmin ? window.ADspaceAdmin.vicTag(r.vic, true) : '') + '</b>' + (r.meta ? '<small>' + esc(r.meta) + '</small>' : '') + '</span>' +
          '<span class="ovw-att-sec"><span class="chip">' + esc(SEC_OF[r.tag] || r.tag) + '</span></span>' +
          '<span class="ovw-att-who">' + (r.who ? esc(r.who) : '<span class="ovw-dash" aria-label="No one">—</span>') + '</span>' +
          '<span class="ovw-att-since">' + since + '</span></button>';
      }).join('');
      var more = list.length - SHOWN;
      var holder = document.createElement('div');
      holder.className = 'ovw-att-rows';
      holder.innerHTML = head + html;
      body.appendChild(holder);
      /* Five rows, then the rest a press away; pressed again, the list
         folds back to five (the user, 2026-10-12: "so it is not
         inadvertently long"; "5 show only"). */
      if (more > 0) body.insertAdjacentHTML('beforeend', '<button class="btn btn-sm ovw-more" type="button" aria-expanded="false" aria-controls="ovwAttention">' +
        '<span>Show ' + more + ' more</span>' + DOWN + '</button>');
      Array.prototype.forEach.call(holder.querySelectorAll('.ovw-att-row'), function (b) {
        var r = list[Number(b.getAttribute('data-i'))];
        b.addEventListener('click', function () { go(r.url, r.section); });
      });
      var mb = body.querySelector('.ovw-more');
      if (mb) mb.addEventListener('click', function () {
        var open = mb.getAttribute('aria-expanded') !== 'true';
        var rs = Array.prototype.slice.call(holder.querySelectorAll('.ovw-att-row')).slice(SHOWN);
        rs.forEach(function (b) { b.hidden = !open; });
        mb.setAttribute('aria-expanded', String(open));
        mb.firstChild.textContent = open ? 'Show fewer' : 'Show ' + more + ' more';
        if (open && rs[0]) rs[0].focus();
        if (!open) { card.scrollIntoView({ block: 'nearest' }); mb.focus({ preventScroll: true }); }
      });
    }
    var run = function () {
      host.innerHTML = '';
      UI.skeleton(body, 4);
      attention().then(function (a) { strip(a); rows(a); })
        .catch(function (e) { fail(body, 'Needs attention', e, run); });
    };
    run();
  }

  /* The bar: the two pages as the view strip at the left, the period and
     the span it reads, with the time it was read, at the right. */
  function bar(box) {
    var head = document.createElement('div');
    head.className = 'ovw-bar';
    head.innerHTML = (hasDetail() ? '<nav class="tabrow ovw-pages" id="ovwPages" role="tablist" aria-label="Dashboard pages">' +
        PAGES.map(function (p) {
          return '<button class="tab' + (p[0] === page ? ' is-on' : '') + '" type="button" role="tab" data-page="' + p[0] + '" aria-selected="' + (p[0] === page) + '"' +
            (p[0] === page ? '' : ' tabindex="-1"') + '><span>' + p[1] + '</span></button>';
        }).join('') + '</nav>' : '') +
      '<span class="ovw-when"><select class="select select-sm" id="ovwPeriod" data-nofind aria-label="Period">' +
      PERIODS.map(function (p) { return '<option value="' + p[0] + '"' + (p[0] === period ? ' selected' : '') + '>' + p[1] + '</option>'; }).join('') +
      '</select><span class="ovw-span" id="ovwSpan"></span></span>';
    box.appendChild(head);
    var strip = head.querySelector('#ovwPages');
    /* A sideways swipe anywhere on the Dashboard turns its page, as the
       strip's tabs do (the user, 2026-10-12; js/swipe.js). */
    var sec = $('sectionOverview');
    if (sec) { if (strip) sec.setAttribute('data-swipe', 'ovwPages'); else sec.removeAttribute('data-swipe'); }
    if (strip) {
      if (window.ADspaceForm && window.ADspaceForm.thumb) window.ADspaceForm.thumb(strip);
      strip.addEventListener('click', function (e) {
        var t = e.target.closest && e.target.closest('.tab');
        if (t) turn(t.getAttribute('data-page'));
      });
      strip.addEventListener('keydown', function (e) {
        if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
        e.preventDefault();
        turn(page === 'summary' ? 'detail' : 'summary');
        var on = $('ovwPages') && $('ovwPages').querySelector('.tab.is-on');
        if (on) on.focus();
      });
    }
    var sel = head.querySelector('select');
    head.querySelector('#ovwSpan').textContent = spanWord(rangeOf(period)) + ' · As at ' + CK.clock(Date.now(), { space: true });
    sel.addEventListener('change', function () {
      if (sel.value === period) return;
      period = sel.value;
      build(true);
      if (bridge.setUrl) bridge.setUrl();
    });
  }

  function build(keep) {
    var box = $('ovwBody');
    if (!box) return;
    var y = keep ? window.scrollY : 0;
    box.innerHTML = '';
    bar(box);
    if (page === 'detail' && hasDetail()) {
      detail(box);
    } else {
      glance(box);
      list(box);
      tiles(box);
      charts(box, PAGE1);
    }
    foot(box);
    if (keep) window.scrollTo(0, y);
    if (keep && $('ovwPeriod')) $('ovwPeriod').focus({ preventScroll: true });
  }
  function urlState() { return { p: period !== 'month' ? period : '', pg: page === 'detail' ? 'detail' : '' }; }

  function enter() {
    var box = $('ovwBody');
    if (!box) return;
    memo = {};
    var want = new URLSearchParams(location.search).get('p');
    period = PERIODS.some(function (p) { return p[0] === want; }) ? want : 'month';
    page = new URLSearchParams(location.search).get('pg') === 'detail' ? 'detail' : 'summary';
    /* Reached with nothing to show (an address from before, or a group whose
       access changed): the console's own first route instead. */
    if (!any() && bridge.show) { bridge.show('work'); return; }
    build(false);
    if (bridge.setUrl) bridge.setUrl();
  }

  window.ADspaceOverview = { enter: enter, urlState: urlState, any: any };
  if (bridge.overviewReady) bridge.overviewReady();
})();
