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
  function esc(s) { return window.ADspaceWords.esc(s); }
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
    if (!r || r.error) throw new Error((r && r.error && r.error.message) || 'The data could not be loaded.');
    if (r.data && r.data.error) throw new Error(r.data.error === 'denied' ? 'You do not have permission to view this. Please ask an admin.' : String(r.data.error));
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
  /* A period is a key of PERIODS, or a span Analytics hands over
     (`{ from, to, prev, name, prevName }`, phase 3, 2026-11-13), so its
     cards read Analytics' own period. */
  function rangeOf(p) {
    if (p && typeof p === 'object') return { from: p.from, to: p.to };
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
    if (p && typeof p === 'object') return p.prev;
    var r = rangeOf(p), n = p === 'quarter' || p === 'lastq' ? 3 : p === 'year' ? 12 : 1;
    return { from: addMonths(r.from, -n), to: addMonths(r.to, -n) };
  }
  function quarterWord(d) { var p = CK.parts(d); return 'Q' + (Math.floor(p.mo / 3) + 1) + ' ' + p.y; }
  // What a change is measured against, in a word: "on Sept", "on last quarter".
  function prevWord(p) {
    if (p && typeof p === 'object') return p.prevName;
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
    if (p && typeof p === 'object') return p.name;
    return p === 'last' ? MON[CK.parts(rangeOf('last').from).mo] : p === 'quarter' ? 'this quarter'
      : p === 'lastq' ? quarterWord(rangeOf('lastq').from) : p === 'year' ? 'this year' : 'this month';
  }
  function delta(now, before) {
    var d = now - before;
    if (!d) return 'Same as ' + prevWord(period);
    return (d > 0 ? '+' : '−') + Math.abs(d) + ' on ' + prevWord(period);
  }

  /* A figure's change with its verdict (the revamp, 2026-11-12): the arrow
     and the Better or Worse that Analytics already judges by, coloured only
     where it is judged; Steady stays ink. `good` the way the figure should
     move. */
  function trendOf(now, before, good, min) {
    var v = S() && S().judge ? S().judge(now, before, good, min) : null;
    var d = now - before;
    /* No change already reads Same as …: Steady would say it twice. */
    return { arrow: !d ? '\u2192' : d > 0 ? '\u2197' : '\u2198', tone: v ? v.tone : 'off', word: v && d ? v.word : '' };
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
          if (!Array.isArray(l)) throw new Error('The data could not be loaded.');
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
    months: function () { return memo.rep6 || reports().then(function () { return memo.rep6 || Promise.reject(new Error('The data could not be loaded.')); }); },
    /* Every client the group reads, once: the sales figures, leads going
       cold, the pipeline and restricted accounts all draw from it. */
    clients: function () {
      return once('clients', function () {
        return API.readPages(function () {
          return db.from('clients').select('id, name, slug, client_code, stage, stage_reason, stage_log, stage_since, created_at, source, owner, market, bill_sgd, ' +
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
          return db.from('ops_tasks').select('id, task_no, title, stage_key, current_final_due_at, delayed_at, delayed_reason, client_id, clients(name, stage)')
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
            /* A thousand rows at a time (the audit of 2026-10-26, finding 4). */
            return API.readPages(function () { return db.rpc('review_set_counts', { p_sets: sets.map(function (s) { return s.id; }) }).order('set_id'); }).then(rows).then(function (counts) {
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
          /* Paged (the audit of 2026-10-26, finding 12): a busy year passed a thousand sets. */
          API.readPages(function () { return db.from('batches').select('id, client_id, created_at').gte('created_at', since.toISOString()).order('created_at', { ascending: false }).order('id'); }).then(rows)
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
    /* A post marked delayed from its month's Accounts Report, until it
       goes live (2026-11-05). */
    { key: 'delayed', word: 'Delayed', title: 'Delayed posts', can: function () { return may('ops', 'manage') && may('ops.all'); }, load: function () {
      return R.openTasks().then(function (list) {
        return list.filter(function (t) { return t.delayed_at && ['live', 'performance_review'].indexOf(t.stage_key) < 0; }).map(function (t) {
          var n = daysSince(t.delayed_at);
          return { name: taskName(t), meta: [(t.clients && t.clients.name) || 'Internal', 'Delayed'].join(' · '), tag: 'Task', who: '', client: t.client_id,
                   late: true, days: n, since: sinceWord(t.delayed_at), taskId: t.id, src: 'delayed',
                   url: '/admin/?s=work&open=' + encodeURIComponent(t.id), section: 'work' };
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
    /* Overdue invoices (2026-10-28): read from Bukku once a visit, a row a
       client opening its Billing (a contact linked to no client, Clients'
       Overdue invoices), never an amount. Bukku not connected lists
       nothing. */
    { key: 'invoices', word: 'Invoices', title: 'Overdue invoices',
      can: function () { return may('clients.billing', 'manage') && !!window.ADspaceInvoices; }, load: function () {
      var owners = canClients() ? R.clients().catch(function () { return []; }) : Promise.resolve([]);
      return Promise.all([once('invoices', function () { return window.ADspaceInvoices.overdue(); }), owners]).then(function (a) {
        var who = {};
        a[1].forEach(function (c) { who[c.id] = c.owner || ''; });
        return a[0].map(function (g) {
          return { name: g.name, meta: g.meta, tag: 'Client', who: (g.client && who[g.client]) || '', client: g.client, late: true, days: g.days,
                   since: daysWord(g.days) + ' late', section: 'clients',
                   url: g.client ? clientUrl({ slug: g.slug, id: g.client }, 'billing') : '/admin/?s=clients&view=overdue' };
        });
      });
    } },
    /* A month completed with no invoice in Bukku (the content loop, phase 3,
       2026-11-10): a row a month, opening the client's Months. */
    { key: 'uninvoiced', word: 'Not invoiced', title: 'Months not invoiced',
      can: function () { return may('clients.billing', 'manage') && may('ops', 'view'); }, load: function () {
      return db.rpc('ops_months_not_invoiced').then(rows).then(function (list) {
        return (list || []).map(function (m) {
          var M = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'], p = String(m.period).split('-');
          return { name: m.name, meta: M[Number(p[1]) - 1] + ' ' + p[0] + (m.checked_at ? ' · Checked ' + window.ADspaceClock.date(m.checked_at) : ''), tag: 'Task', who: m.owner || '',
                   client: m.client, days: daysSince(m.since), since: sinceWord(m.since), tone: 'warn',
                   url: '/admin/?s=work&view=months&wc=' + encodeURIComponent(m.slug || m.client), section: 'work' };
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
        return { failed: typeof s.title === 'function' ? s.title() : s.title, why: (e && e.message) || 'The data could not be loaded.' };
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
  function kindTile(key, title, kind, good) {
    return { key: key, title: title, sec: 'clients', can: canLeads, to: 'moved', load: function () {
      return Promise.all([figuresFor('now'), figuresFor('prev'), figuresFor('six')]).then(function (f) {
        return { fig: String(f[0][kind].length), sub: delta(f[0][kind].length, f[1][kind].length),
                 trend: trendOf(f[0][kind].length, f[1][kind].length, good, 2),
                 spark: f[2].months.map(function (m) { return m[kind]; }) };
      });
    } };
  }
  /* ---- The tiles -------------------------------------------------------------------
     A tile: its label, its figure, one line under it and, where the figure
     has a history, its trend. `load()` answers `{ fig, sub, tone, spark,
     bar }`. */
  var SALES = [
    kindTile('leads', 'New leads', 'newLeads', 'up'),
    kindTile('won', 'Won', 'won', 'up'),
    kindTile('churned', 'Churned', 'churned', 'down'),
    /* Committed monthly value for whoever may open a client's Services, from
       the lines that part opens; Active clients for everyone else. */
    { key: 'value', sec: 'clients', title: function () { return canValue() ? 'Committed monthly value' : 'Active clients'; },
      /* Its narrow word: the whole label is cut at a phone's tile (2026-10-15, audit OVW-1). */
      short: function () { return canValue() ? 'Committed value' : ''; }, can: canClients,
      to: function () { return canValue() ? 'valueby' : ''; }, load: function () {
      if (canValue()) {
        return R.lines().then(function (lines) { return figuresFor('now', lines); }).then(function (f) {
          var won = f.money && f.money.won, any = won && Object.keys(won).some(function (k) { return won[k]; });
          return { fig: moneyWord(f.money && f.money.active), money: true,
                   sub: any ? moneyWord(won) + ' won ' + periodName(period) : 'None won ' + periodName(period) };
        });
      }
      return Promise.all([figuresFor('now'), figuresFor('six')]).then(function (f) {
        return { fig: String(f[0].activeEnd), sub: delta(f[0].activeEnd, f[0].activeStart),
                 trend: trendOf(f[0].activeEnd, f[0].activeStart, 'up', 2),
                 spark: f[1].months.map(function (m) { return m.active; }) };
      });
    } }
  ];
  function completed(d) {
    return (d && Array.isArray(d.by_person) ? d.by_person : []).reduce(function (a, p) { return a + (Number(p.completed) || 0); }, 0);
  }
  var OPS = [
    /* On time (the revamp, 2026-11-12, in place of the rings): the share of
       the work due in the period delivered by its date, work still late
       counted against it, as the rings read it. */
    { key: 'ontime', title: 'On time', sec: 'work', can: canFigures, load: function () {
      return Promise.all([R.report(), R.reportPrev()]).then(function (r) {
        var rate = function (d) {
          var f = d.on_time || {}, n = Number(f.reached || 0) + Number(f.late_open || 0);
          return n ? Math.round(Number(f.met || 0) / n * 100) : null;
        };
        var now = rate(r[0]), before = rate(r[1]);
        if (now == null) return { fig: '\u2014', sub: 'None due' };
        var d = before == null ? null : now - before;
        return { fig: now + '%', bar: now / 100,
                 sub: d == null ? '' : !d ? 'Same as ' + prevWord(period) : (d > 0 ? '+' : '\u2212') + Math.abs(d) + (Math.abs(d) === 1 ? ' point on ' : ' points on ') + prevWord(period),
                 trend: d == null ? null : trendOf(now, before, 'up', 2) };
      });
    } },
    /* The count is the Late tasks signal's; the tile states how late the
       oldest is, so nothing on the page is said twice (2026-10-22, OVW-5). */
    { key: 'late', title: 'Oldest late', sec: 'work', can: canFigures, load: function () {
      /* Its trend is the work delivered late each of the last six months
         (phase 4, 2026-11-13): how late a task is cannot be read back. */
      var lateBy = function (x) { return (x.d.by_person || []).reduce(function (a, p) { return a + Math.max(0, (Number(p.completed) || 0) - (Number(p.on_time) || 0)); }, 0); };
      return Promise.all([R.report(), R.months().catch(function () { return null; })]).then(function (q) {
        var d = q[0], spark = q[1] ? q[1].map(lateBy) : null;
        var l = d.late || [], oldest = l.reduce(function (a, t) { return a && (Number(a.days_over) || 0) >= (Number(t.days_over) || 0) ? a : t; }, null);
        var top = oldest ? Number(oldest.days_over) || 0 : 0;
        /* Which task it is, and whose, so the tile names what to open (the
           user, 2026-11-13: the tile read as half empty on a phone). */
        return { fig: l.length ? daysWord(top) : 'None', tone: l.length ? 'err' : '', spark: spark && spark.some(Boolean) ? spark : null,
                 sub: oldest ? [oldest.title, oldest.client].filter(Boolean).join(' · ') : 'No work is late' };
      });
    } },
    { key: 'delivered', title: function () { return 'Delivered ' + periodName(period); }, short: function () { return 'Delivered'; }, sec: 'work', can: canFigures, load: function () {
      return Promise.all([R.report(), R.reportPrev(), R.months()]).then(function (r) {
        var n = completed(r[0]);
        return { fig: String(n), sub: delta(n, completed(r[1])), trend: trendOf(n, completed(r[1]), 'up', 2), spark: r[2].map(function (x) { return completed(x.d); }) };
      });
    } },
    { key: 'published', title: function () { return 'Reports published, ' + lastMonth().short; }, sec: 'reports', can: canReports, load: function () {
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
  /* Clients who moved: each kind of move with its words, in the order a
     sale runs. */
  var MOVED = [['won', 'Won'], ['newLeads', 'New leads'], ['lost', 'Lost leads'], ['churned', 'Churned'],
               ['paused', 'Paused'], ['resumed', 'Resumed'], ['winback', 'Win-backs']];
  var MOVED_SHOWN = 5;
  /* A client in a card's table: its name over its Client ID, opening its record. */
  /* The chevron of every Show N more on the Dashboard. */
  var DOWN = '<svg class="ovw-more-chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 9l6 6 6-6"/></svg>';
  function clientButton(c, tab) {
    return '<button type="button" class="linkbtn ovw-client" data-go="' + esc(clientUrl(c, tab)) + '">' +
      '<span>' + esc(c.name || 'Untitled client') + '</span>' + (c.client_code ? '<small>' + esc(c.client_code) + '</small>' : '') + '</button>';
  }
  function wireClients(body) {
    body.addEventListener('click', function (e) {
      var b = e.target.closest('.ovw-client');
      if (b) { go(b.getAttribute('data-go'), 'clients'); return; }
      var m = e.target.closest('.ovw-more');
      if (!m) return;
      var open = m.getAttribute('aria-expanded') !== 'true', tb = m.closest('tbody');
      Array.prototype.forEach.call(tb.querySelectorAll('tr.is-more'), function (r) { r.hidden = !open; });
      m.setAttribute('aria-expanded', String(open));
      m.textContent = open ? 'Show fewer' : 'Show ' + m.getAttribute('data-n') + ' more';
    });
  }
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
      /* Who is behind each count (the user, 2026-11-12: the tiles said how
         many were won or churned, never who): every client a move counted
         in the period, by move, each opening its record. */
      { key: 'moved', title: 'Clients who moved', can: canLeads,
        all: ['Clients', '/admin/?s=clients', 'clients'], load: function () {
        return figuresFor('now').then(function (f) {
          var kinds = MOVED.filter(function (k) { return f[k[0]].length; });
          if (!kinds.length) return { empty: 'Nothing moved ' + periodName(period) + '.' };
          return { html: '<div class="chart-tblwrap"><table class="chart-tbl ovw-tbl ovw-moved"><thead><tr><th scope="col">Client</th>' +
            '<th scope="col" class="ovw-who">Person in charge</th><th scope="col" class="is-end">Date</th></tr></thead>' +
            kinds.map(function (k) {
              var list = f[k[0]].slice().sort(function (a, b) {
                return String(f.at[k[0]][b.id] || '').localeCompare(String(f.at[k[0]][a.id] || ''));
              });
              return '<tbody data-kind="' + k[0] + '"><tr class="ovw-tbl-group"><th scope="rowgroup" colspan="3">' + esc(k[1]) +
                ' <span class="tab-n">' + list.length + '</span></th></tr>' +
                list.map(function (c, i) {
                  return '<tr' + (i >= MOVED_SHOWN ? ' class="is-more" hidden' : '') + '><th scope="row">' + clientButton(c, '') + '</th>' +
                    '<td class="ovw-who">' + esc(c.owner || '\u2014') + '</td><td class="is-end">' + esc(shortDate(f.at[k[0]][c.id])) + '</td></tr>';
                }).join('') +
                (list.length > MOVED_SHOWN ? '<tr class="ovw-tbl-more"><td colspan="3"><button type="button" class="btn btn-quiet btn-sm ovw-more" aria-expanded="false" data-n="' +
                  (list.length - MOVED_SHOWN) + '">Show ' + (list.length - MOVED_SHOWN) + ' more</button></td></tr>' : '') +
                '</tbody>';
            }).join('') + '</table></div>', wire: wireClients };
        });
      } },
      /* What makes up Committed monthly value (the same day): each active
         client's month of confirmed monthly lines, highest first, a total a
         currency, each opening the client's Services. */
      { key: 'valueby', title: 'Committed monthly value by client', can: function () { return canClients() && canValue(); },
        all: ['Clients', '/admin/?s=clients', 'clients'], load: function () {
        return R.lines().then(function (lines) { return figuresFor('now', lines); }).then(function (f) {
          var by = (f.money && f.money.byClient) || {}, M = window.ADspaceMoney;
          var cur = function (c) { return M ? M.curOf(c) : String(c.market || 'MY').toUpperCase(); };
          var list = f.activeNow.filter(function (c) { return by[c.id] > 0; }).sort(function (a, b) {
            return cur(a).localeCompare(cur(b)) || by[b.id] - by[a.id] || String(a.name).localeCompare(String(b.name));
          });
          if (!list.length) return { empty: 'No committed monthly value.' };
          var total = {};
          list.forEach(function (c) { total[cur(c)] = (total[cur(c)] || 0) + by[c.id]; });
          return { html: '<div class="chart-tblwrap"><table class="chart-tbl ovw-tbl ovw-valueby"><thead><tr><th scope="col">Client</th>' +
            '<th scope="col" class="is-end">Per month</th><th scope="col" class="is-end ovw-share">Share</th></tr></thead><tbody>' +
            list.map(function (c) {
              var k = cur(c);
              return '<tr><th scope="row">' + clientButton(c, 'services') + '</th><td class="is-end">' + esc(M ? M.money2(by[c.id], k) : by[c.id].toFixed(2)) +
                '</td><td class="is-end ovw-share">' + Math.round(by[c.id] / total[k] * 100) + '%</td></tr>';
            }).join('') + '</tbody><tfoot>' + Object.keys(total).sort().map(function (k) {
              return '<tr><th scope="row">Total</th><td class="is-end">' + esc(M ? M.money2(total[k], k) : total[k].toFixed(2)) + '</td><td class="is-end ovw-share">100%</td></tr>';
            }).join('') + '</tfoot></table></div>', wire: wireClients };
        });
      } }
      ],
      [
      { key: 'sources', title: 'New leads by source', can: canLeads,
        all: ['Clients', '/admin/?s=clients', 'clients'], load: function () {
        return figuresFor('now').then(function (f) {
          var rowsOf = Object.keys(f.bySource).map(function (k) { var C = window.ADspaceCRM; return { label: C && C.sourceWord ? C.sourceWord(k) : k, value: f.bySource[k].length }; })
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
  /* What Team draws: Needs attention's sources, the four figures, Work by
     person, Clients this month and the on-time trend. */
  function teamAny() {
    return SOURCES.some(function (c) { return c.can(); }) || canFigures() || canTeamWork() ||
      SALES.concat(OPS).some(function (t) { return LEAD.indexOf(t.key) > -1 && t.can(); });
  }

  // ---- Drawing ----------------------------------------------------------------------
  function fail(body, title, e, again) {
    UI.failLine(body, title || 'This card', (e && e.message) || 'The data could not be loaded.', again);
  }
  function tile(grid, t) {
    var el = document.createElement('article');
    el.className = 'chartcard ovw-kpi';
    el.setAttribute('data-tile', t.key);
    el.innerHTML = '<span class="ovw-kpi-label"></span><b class="ovw-kpi-fig"><span class="skel skel-w"></span></b>' +
      '<span class="ovw-kpi-line"><span class="ovw-kpi-sub"></span></span><span class="ovw-kpi-trend"></span>';
    /* The section the figure is read from, its mark at the tile's top right. */
    var mark = t.sec && window.ADspaceAdmin && window.ADspaceAdmin.glyph ? window.ADspaceAdmin.glyph(t.sec) : '';
    if (mark) { el.classList.add('has-mark'); el.insertAdjacentHTML('afterbegin', '<span class="ovw-kpi-mark" aria-hidden="true">' + mark + '</span>'); }
    label(el, t);
    grid.appendChild(el);
    /* A count with clients behind it opens them on Detail (2026-11-12). */
    var to = typeof t.to === 'function' ? t.to() : t.to;
    var open = function (e) {
      if (!el.classList.contains('is-link') || e.target.closest('button')) return;
      if (e.type === 'keydown' && e.key !== 'Enter' && e.key !== ' ') return;
      e.preventDefault();
      openCard(to);
    };
    if (to) { el.addEventListener('click', open); el.addEventListener('keydown', open); }
    var run = function () {
      t.load().then(function (o) {
        if (to) {
          el.classList.add('is-link'); el.setAttribute('role', 'button'); el.tabIndex = 0;
          el.setAttribute('aria-label', titleOf(t) + ': ' + o.fig + '. Show the clients');
        }
        var fig = el.querySelector('.ovw-kpi-fig');
        fig.textContent = o.fig;
        fig.className = 'ovw-kpi-fig' + (o.tone ? ' is-' + o.tone : '') + (o.money ? ' is-money' : '');
        label(el, t);
        el.querySelector('.ovw-kpi-sub').textContent = o.sub || '';
        var line = el.querySelector('.ovw-kpi-line');
        Array.prototype.forEach.call(line.querySelectorAll('.ovw-kpi-arrow, .ovw-kpi-verdict'), function (x) { x.remove(); });
        line.className = 'ovw-kpi-line' + (o.trend && o.sub ? ' is-' + o.trend.tone : '');
        if (o.trend && o.sub) {
          line.insertAdjacentHTML('afterbegin', '<i class="ovw-kpi-arrow" aria-hidden="true">' + o.trend.arrow + '</i>');
          if (o.trend.word) line.insertAdjacentHTML('beforeend', '<span class="ovw-kpi-verdict">' + esc(o.trend.word) + '</span>');
        }
        el.querySelector('.ovw-kpi-trend').innerHTML = o.bar != null
          ? '<span class="ovw-kpi-bar" aria-hidden="true"><i style="width:' + Math.round(o.bar * 100) + '%"></i></span>'
          : (o.spark ? CH.spark(o.spark, o.tone) : '');
      }).catch(function (e) {
        el.classList.remove('is-link'); el.removeAttribute('role'); el.removeAttribute('tabindex'); el.removeAttribute('aria-label');
        el.querySelector('.ovw-kpi-fig').textContent = '—';
        el.querySelector('.ovw-kpi-sub').innerHTML = '';
        var b = document.createElement('button');
        b.type = 'button'; b.className = 'btn btn-quiet btn-sm ovw-kpi-again'; b.textContent = 'Try again';
        b.setAttribute('aria-label', 'Try again: ' + titleOf(t) + '. ' + ((e && e.message) || 'The data could not be loaded.'));
        b.addEventListener('click', function () { el.querySelector('.ovw-kpi-sub').textContent = ''; run(); });
        el.querySelector('.ovw-kpi-sub').appendChild(document.createTextNode('Could not load. '));
        el.querySelector('.ovw-kpi-sub').appendChild(b);
      });
    };
    run();
  }
  /* The four figures that lead the page (the revamp, 2026-11-12): one row,
     before everything else. The rest stay in their groups further down. */
  var LEAD = ['delivered', 'ontime', 'leads', 'late'];
  function lead(box) {
    var all = SALES.concat(OPS), list = LEAD.map(function (k) {
      return all.filter(function (t) { return t.key === k; })[0];
    }).filter(function (t) { return t && t.can(); });
    if (!list.length) return;
    var grid = document.createElement('div');
    grid.className = 'ovw-kpis ovw-lead';
    grid.id = 'ovwLead';
    box.appendChild(grid);
    list.forEach(function (t) { tile(grid, t); });
  }
  function tiles(box, only) {
    /* On Analytics (`only`) the period's own Delivered and On time join
       their group; Oldest late and New leads stay the Dashboard's. */
    var rest = function (t) { return (only ? ['late', 'leads'] : LEAD).indexOf(t.key) < 0 && t.can(); };
    var groups = [['Sales', SALES, 'ovwSales'], ['Operations', OPS, 'ovwOps']].filter(function (g) { return !only || g[0] === only; }).map(function (g) {
      return { head: g[0], list: g[1].filter(rest), id: g[2] };
    }).filter(function (g) { return g.list.length; });
    if (!groups.length) return;
    var wrap = document.createElement('div');
    wrap.className = 'ovw-groups' + (groups.length === 1 ? ' is-one' : '');
    box.appendChild(wrap);
    groups.forEach(function (g) {
      var sec = document.createElement('section');
      sec.className = 'ovw-group';
      sec.id = g.id;
      sec.innerHTML = '<h3 class="ovw-group-h"></h3><div class="ovw-kpis is-n' + g.list.length + '"></div>';
      /* The tab already names the group on Analytics. */
      if (only) sec.firstChild.remove(); else sec.firstChild.textContent = g.head;
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
        if (out.html) { body.innerHTML = out.html; if (out.wire) out.wire(body); return; }
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
  /* Team detail moved to Analytics (phase 3, 2026-11-13; the user:
     "Analytics follows each chart's section access"): Analytics asks
     whether a group holds any card it may read, and draws that group's
     tiles and charts on its own period. */
  function groupOf(name) { return PAGE2.filter(function (g) { return g[0] === name; })[0]; }
  function groupCan(name) {
    var g = groupOf(name), list = name === 'Sales' ? SALES : OPS;
    return list.some(function (t) { return ['late', 'leads'].indexOf(t.key) < 0 && t.can(); }) ||
      Boolean(g && g[1].some(function (row) { return row.some(function (c) { return c.can(); }); }));
  }
  function forAnalytics(box, name, spec, skip) {
    period = spec;
    memo = {};
    tiles(box, name);
    Array.prototype.forEach.call(box.querySelectorAll('[id^="ovw"]'), function (n) { n.removeAttribute('id'); });
    var g = groupOf(name);
    /* A card Analytics already draws on the tab is left out (`skip`). */
    if (g) charts(box, g[1].map(function (row) { return row.filter(function (c) { return (skip || []).indexOf(c.key) < 0; }); }));
  }
  /* Two pages (the revamp, 2026-11-13; the user: the Dashboard for every
     colleague): Me, each colleague's own work, offered to everyone; Team,
     for a group whose Team dashboard is on and one of whose cards is
     allowed. */
  var PAGES = [['me', 'Me'], ['summary', 'Team']];
  var page = 'me';
  function teamOk() {
    var me = bridge.me && bridge.me();
    if (!me) return false;
    if (!(me.is_admin || me.role === 'admin') && (me.access || {}).overview === 'none') return false;
    return teamAny();
  }
  function pagesShown() {
    return PAGES.filter(function (p) { return p[0] === 'me' || teamOk(); });
  }
  /* A page turn slides (the user, 2026-10-12: the swap "felt too fast,
     lacking the proper sliding"): the page left moves out to one side as
     the new one comes in from the other, Detail from the right and Summary
     from the left, the bar and its strip holding still. The page left is a
     still copy laid where it stood on screen, gone once the slide ends. */
  var ghostGone = null;
  function turn(to) {
    if (to === page) return;
    var box = $('ovwBody'), sec = $('sectionOverview');
    var order = PAGES.map(function (p) { return p[0]; });
    var dir = order.indexOf(to) > order.indexOf(page) ? 'next' : 'prev';
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
    keepPage();
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
  /* A tile with clients behind it opens their card: on this page where it
     stands (Analytics), else on Analytics' Sales tab. */
  function openCard(key) {
    var here = document.querySelector('#sectionAnalytics:not([hidden]) [data-card="' + key + '"]');
    if (!here) {
      try { sessionStorage.setItem('adspace-anl-card', key); } catch (e) { /* the tab opens at its top */ }
      go('/admin/?s=analytics', 'analytics');
      return;
    }
    focusCard(here);
  }
  function focusCard(c) {
    c.scrollIntoView({ block: 'start' });
    var h = c.querySelector('.ovw-cardhead h3');
    if (h) { h.tabIndex = -1; h.focus({ preventScroll: true }); }
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
    /* Its four columns need 620px: beside the on-time chart in a narrowed
       window the card is narrower than that, so it takes the phone's two-line
       row there (the user, 2026-11-13: the names broke and overran the rows). */
    card.setAttribute('data-narrow', '620');
    card.innerHTML = '<div class="ovw-cardhead"><h3>Needs attention</h3><span class="ovw-count" hidden></span></div><div class="ovw-srcs-host"></div><div class="ovw-body"></div>';
    box.appendChild(card);
    if (window.ADspaceState && window.ADspaceState.fit) window.ADspaceState.fit('#ovwAttention');
    var body = card.querySelector('.ovw-body'), host = card.querySelector('.ovw-srcs-host');
    var pick = '';
    var SEC_OF = { Task: 'My Work', Report: 'Reports', Lead: 'Clients', Client: 'Clients', Request: 'Clients',
      Document: 'Clients', Campaign: 'Creator Campaigns', Performance: 'Team' };
    /* The section's mark before its name (the revamp, 2026-11-12). */
    var SEC_KEY = { 'My Work': 'work', Reports: 'reports', Clients: 'clients', 'Creator Campaigns': 'campaigns', Team: 'team' };
    function secMark(word) {
      var k = SEC_KEY[word], A = window.ADspaceAdmin;
      return k && A && A.glyph ? '<span class="ovw-att-mark" aria-hidden="true">' + A.glyph(k) + '</span>' : '';
    }
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
          '<span class="ovw-att-sec">' + secMark(SEC_OF[r.tag] || r.tag) + '<span class="ovw-att-secword">' + esc(SEC_OF[r.tag] || r.tag) + '</span></span>' +
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
    var shown = pagesShown();
    head.innerHTML = (shown.length > 1 ? '<nav class="tabrow ovw-pages" id="ovwPages" role="tablist" aria-label="Dashboard pages">' +
        shown.map(function (p) {
          return '<button class="tab' + (p[0] === page ? ' is-on' : '') + '" type="button" role="tab" data-page="' + p[0] + '" aria-selected="' + (p[0] === page) + '"' +
            (p[0] === page ? '' : ' tabindex="-1"') + '><span>' + p[1] + '</span></button>';
        }).join('') + '</nav>' : '') +
      (page === 'me' ? '' : '<span class="ovw-when"><select class="select select-sm" id="ovwPeriod" data-nofind aria-label="Period">' +
      PERIODS.map(function (p) { return '<option value="' + p[0] + '"' + (p[0] === period ? ' selected' : '') + '>' + p[1] + '</option>'; }).join('') +
      '</select><span class="ovw-span" id="ovwSpan"></span></span>');
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
        var keys = shown.map(function (p) { return p[0]; }), i = keys.indexOf(page);
        var to = keys[(i + (e.key === 'ArrowRight' ? 1 : keys.length - 1)) % keys.length];
        turn(to);
        var on = $('ovwPages') && $('ovwPages').querySelector('.tab.is-on');
        if (on) on.focus();
      });
    }
    var sel = head.querySelector('select');
    if (!sel) return;
    head.querySelector('#ovwSpan').textContent = spanWord(rangeOf(period)) + ' · As at ' + CK.clock(Date.now(), { space: true });
    sel.addEventListener('change', function () {
      if (sel.value === period) return;
      period = sel.value;
      build(true);
      if (bridge.setUrl) bridge.setUrl();
    });
  }

  // ---- Me: each colleague's own page (the revamp, 2026-11-13) -----------------
  /* The greeting heads the Dashboard (the user, 2026-11-13): Good morning
     from 4:00am to 11:59am, Good afternoon from noon to 3:59pm, Good evening
     from 4pm to 8:59pm, Good night from 9pm to 3:59am, on Malaysia's clock,
     to the colleague by their whole name; the date under it. */
  function greetWord(h) {
    return h >= 4 && h < 12 ? 'Good morning' : h >= 12 && h < 16 ? 'Good afternoon' : h >= 16 && h < 21 ? 'Good evening' : 'Good night';
  }
  function greet() {
    var me = bridge.me && bridge.me(), t = $('sectionTitle');
    if (!t) return;
    var name = String((me && me.name) || '').trim(), words = greetWord(CK.parts(Date.now()).h) + (name ? ', ' + name : '');
    var w = t.querySelector('.console-title-word');
    if (w) w.textContent = words;
    t.setAttribute('aria-label', words + '. Dashboard, about this section');
    var crumb = $('sectionCrumb');
    if (crumb) { crumb.textContent = CK.date(CK.today(), { weekday: true, year: false }); crumb.hidden = false; }
  }
  // ---- Team: who and which client is at risk (the revamp, phase 2) -----------
  /* A task's ring (phase 4, the user, 2026-11-13): the outer line the time
     used from its assignment to the end of its final date, the inner fill
     its checklist done. Green while the work keeps up, amber once the time
     runs more than 20 points ahead of the work (with no checklist, once 80%
     of the time is gone), red once late. Nothing is drawn with no date. */
  function ringOf(t) {
    if (!t || !t.finalAt || !t.from) return '';
    var from = Date.parse(t.from), end = Date.parse(CK.day(t.finalAt) + 'T23:59:59+08:00');
    if (isNaN(from) || isNaN(end)) return '';
    var used = end > from ? (Date.now() - from) / (end - from) : 1;
    used = Math.max(0, Math.min(1, used));
    var w = t.checks ? t.checks.done / t.checks.of : null;
    var tone = t.late ? 'late' : (w == null ? used >= 0.8 : used - w > 0.2) ? 'wait' : 'ok';
    var say = 'Time used ' + Math.round(used * 100) + '%. ' + (t.checks ? 'Checklist ' + t.checks.done + ' of ' + t.checks.of + ' done.' : 'No checklist.');
    return '<span class="ovw-ring is-' + tone + '" role="img" aria-label="' + esc(say) + '" title="' + esc(say) + '"><svg viewBox="0 0 36 36" aria-hidden="true">' +
      '<circle class="r-track" cx="18" cy="18" r="15.5"/>' +
      '<circle class="r-time" cx="18" cy="18" r="15.5" pathLength="100" stroke-dasharray="' + (used * 100).toFixed(1) + ' 100"/>' +
      '<circle class="r-in" cx="18" cy="18" r="10.5"/>' +
      (w ? '<circle class="r-work" cx="18" cy="18" r="5.25" pathLength="100" stroke-dasharray="' + (w * 100).toFixed(1) + ' 100"/>' : '') +
      '</svg></span>';
  }

  var TEAM = (function () {
    function card(host, id, title, to) {
      var c = document.createElement('section');
      c.className = 'chartcard ovw-card ovw-tbl';
      c.id = id;
      c.innerHTML = '<h3 class="chart-title"></h3><div class="ovw-body"></div>';
      headOf(c, title, to);
      host.appendChild(c);
      return c.querySelector('.ovw-body');
    }
    function pc(a, b) { return b ? Math.round(a / b * 100) + '%' : '—'; }
    /* Work by stage (phase 4, 2026-11-13; the user's Workload strip): a
       ring a stage holding open work, split by how its work stands: on
       track light grey, due within two days amber, late red (the late rule
       My Work reads); its count in the middle and who holds it under its
       name; a stage opens My Work's board. */
    function stages(host) {
      if (!canTeamWork()) return;
      var body = card(host, 'ovwStages', 'Work by stage', ['My Work', '/admin/?s=work&view=board', 'work']);
      var run = function () {
        UI.skeleton(body, 2);
        Promise.all([R.report(), R.openTasks()]).then(function (q) {
          var d = q[0], by = {}, order = [], byKey = {}, lateIds = {};
          (d.running || []).forEach(function (r) {
            var k = r.label || r.stage_key;
            byKey[r.stage_key] = k;
            if (!by[k]) { by[k] = { label: k, n: 0, late: 0, soon: 0, pos: Number(r.position) || 0, who: {} }; order.push(k); }
            by[k].n += Number(r.count) || 0;
            by[k].pos = Math.min(by[k].pos, Number(r.position) || 0);
          });
          (d.late || []).forEach(function (t) { lateIds[t.task_id] = true; if (by[t.stage]) by[t.stage].late++; });
          var tasks = q[1] || [], soonTo = CK.addDays(CK.today(), 2);
          tasks.forEach(function (t) {
            var st = by[byKey[t.stage_key]];
            if (!st || lateIds[t.id] || !t.current_final_due_at) return;
            var dd = CK.day(t.current_final_due_at);
            if (dd >= CK.today() && dd <= soonTo) st.soon++;
          });
          var list = order.map(function (k) { return by[k]; }).filter(function (x) { return x.n > 0; })
            .sort(function (a, b) { return a.pos - b.pos || a.label.localeCompare(b.label); });
          if (!list.length) { body.innerHTML = ''; UI.emptyLine(body, 'No open tasks.'); return null; }
          /* Who holds each stage's work: the owners of the open tasks, read
             for those tasks alone, a 150 a request; a refused read leaves the
             discs off. */
          var ids = tasks.map(function (t) { return t.id; }), parts = [], stageOf = {};
          tasks.forEach(function (t) { stageOf[t.id] = byKey[t.stage_key]; });
          for (var i = 0; i < ids.length; i += 150) parts.push(ids.slice(i, i + 150));
          return Promise.all(parts.map(function (part) {
            return db.from('ops_task_assignees').select('task_id, team_members!ops_task_assignees_team_member_id_fkey(name)')
              .in('task_id', part).eq('responsibility', 'owner').is('ended_at', null).then(rows).catch(function () { return []; });
          })).then(function (rs) {
            rs.forEach(function (l) {
              (l || []).forEach(function (a) {
                var st = by[stageOf[a.task_id]], nm = a.team_members && a.team_members.name;
                if (st && nm) st.who[nm] = (st.who[nm] || 0) + 1;
              });
            });
            var A = window.ADspaceAdmin;
            body.innerHTML = '<div class="ovw-stages">' + list.map(function (x) {
              x.soon = Math.min(x.soon, x.n - x.late);
              var names = Object.keys(x.who).sort(function (a, b) { return x.who[b] - x.who[a] || a.localeCompare(b); });
              var ok = x.n - x.late - x.soon, parts = [['ok', ok], ['soon', x.soon], ['late', x.late]].filter(function (p) { return p[1] > 0; });
              var say = x.label + ': ' + x.n + ' open' + (x.soon ? ', ' + x.soon + ' due within 2 days' : '') + (x.late ? ', ' + x.late + ' late' : '') +
                (names.length ? '. Assigned to ' + names.join(', ') : '');
              var off = 0, gap = parts.length > 1 ? 1.5 : 0;
              var ring = '<svg viewBox="0 0 64 64" aria-hidden="true"><circle class="r-track" cx="32" cy="32" r="27"/>' + parts.map(function (p) {
                var len = p[1] / x.n * 100, c = '<circle class="r-part is-' + p[0] + '" cx="32" cy="32" r="27" pathLength="100" stroke-dasharray="' +
                  Math.max(0.5, len - gap).toFixed(1) + ' 100" stroke-dashoffset="' + (-off).toFixed(1) + '"/>';
                off += len;
                return c;
              }).join('') + '<text x="32" y="32" dominant-baseline="central" text-anchor="middle">' + x.n + '</text></svg>';
              var discs = names.slice(0, 3).map(function (nm) { return A && A.avatar ? A.avatar(nm) : ''; }).join('') +
                (names.length > 3 ? '<span class="ovw-stage-more">+' + (names.length - 3) + '</span>' : '');
              return '<button class="ovw-stage" type="button" aria-label="' + esc(say) + '">' + ring + '<b>' + esc(x.label) + '</b>' +
                '<span class="ovw-stage-who">' + discs + '</span></button>';
            }).join('') + '</div><p class="ovw-stage-key"><span class="is-ok">On track</span><span class="is-soon">Due within 2 days</span><span class="is-late">Late</span></p>';
            Array.prototype.forEach.call(body.querySelectorAll('.ovw-stage'), function (b) {
              b.addEventListener('click', function () { go('/admin/?s=work&view=board', 'work'); });
            });
          });
        }).catch(function (e) { fail(body, 'Work by stage', e, run); });
      };
      run();
    }
    /* People: each colleague's open work and what of it is late now, and
       what they delivered in the period and how much of it on time, from
       the report the page already reads; late first, then the most open.
       A row opens the colleague's own Work. */
    function people(host) {
      if (!canTeamWork()) return;
      var body = card(host, 'ovwPeople', 'Work by person', ['My Work', '/admin/?s=work', 'work']);
      var run = function () {
        UI.skeleton(body, 3);
        R.report().then(function (d) {
          if (!Array.isArray(d.open_by_person)) throw new Error('This feature is not available yet. Please contact an admin.');
          var by = {};
          d.open_by_person.forEach(function (r) {
            if (!r.team_member_id) return;
            by[r.team_member_id] = { id: r.team_member_id, name: r.name, open: Number(r.open) || 0, late: Number(r.late) || 0, done: 0, on: 0 };
          });
          (d.by_person || []).forEach(function (x) {
            var id = x.team_member_id || x.id;
            if (!id) return;
            var p = by[id] || (by[id] = { id: id, name: x.name, open: 0, late: 0, done: 0, on: 0 });
            p.done = Number(x.completed) || 0; p.on = Number(x.on_time) || 0;
          });
          var list = Object.keys(by).map(function (k) { return by[k]; }).filter(function (p) { return p.open || p.done; })
            .sort(function (a, b) { return (b.late > 0) - (a.late > 0) || b.late - a.late || b.open - a.open || String(a.name).localeCompare(String(b.name)); });
          if (!list.length) { body.innerHTML = ''; UI.emptyLine(body, 'No open tasks.'); return; }
          var open = may('team', 'view'), most = list.reduce(function (m, p) { return Math.max(m, p.open); }, 1);
          body.innerHTML = '<div class="ovw-tr ovw-th is-people"><span>Colleague</span><span>Open</span><span>Late</span><span class="ovw-hide-n">Delivered</span><span>On time</span></div>' +
            list.map(function (p) {
              var A = window.ADspaceAdmin, disc = A && A.avatar ? A.avatar(p.name) : '';
              /* The open work as a bar on one scale, its late part red
                 (phase 4, 2026-11-13). */
              var bar = '<span class="ovw-pbar" aria-hidden="true"><i style="width:' + ((p.open - p.late) / most * 100).toFixed(1) + '%"></i>' +
                (p.late ? '<i class="is-late" style="width:' + (p.late / most * 100).toFixed(1) + '%"></i>' : '') + '</span>';
              var cells = '<span class="ovw-who">' + disc + '<span class="ovw-who-t"><b>' + esc(p.name) + '</b>' + bar + '</span></span>' +
                '<span class="ovw-n">' + p.open + '</span>' +
                '<span class="ovw-n' + (p.late ? ' is-late' : '') + '">' + (p.late || '—') + '</span>' +
                '<span class="ovw-n ovw-hide-n">' + (p.done || '—') + '</span>' +
                '<span class="ovw-n">' + pc(p.on, p.done) + '</span>';
              return open ? '<button class="ovw-tr is-people" type="button" data-go="/admin/?s=team&member=' + esc(encodeURIComponent(p.id)) + '&mtab=work">' + cells + '</button>'
                : '<div class="ovw-tr is-people">' + cells + '</div>';
            }).join('');
          Array.prototype.forEach.call(body.querySelectorAll('[data-go]'), function (b) {
            b.addEventListener('click', function () { go(b.getAttribute('data-go'), 'team'); });
          });
        }).catch(function (e) { fail(body, 'People', e, run); });
      };
      run();
    }
    /* Clients this month: each client whose content month is this month, its
       work done of planned and what is late, its report for last month and
       its next meeting; late first, then the least done. A row opens the
       client's Months in My Work. */
    function clients(host) {
      if (!canFigures() || !may('ops', 'view')) return;
      var body = card(host, 'ovwClientsMonth', 'Clients this month', ['My Work', '/admin/?s=work&view=months', 'work']);
      var key = CK.today().slice(0, 7);
      var run = function () {
        UI.skeleton(body, 3);
        Promise.resolve().then(function () {
          return db.from('ops_engagements').select('id, client_id, period, status, meeting_at, meeting_na, clients(name, logo_url, stage)').eq('period', key);
        }).then(rows).then(function (eng) {
          eng = (eng || []).filter(function (e) { return e.status !== 'cancelled' && e.clients && e.clients.stage !== 'past'; });
          if (!eng.length) { body.innerHTML = ''; UI.emptyLine(body, 'No client month this month.'); return null; }
          return Promise.all([
            db.rpc('ops_engagement_counts', { p_engagements: eng.map(function (e) { return e.id; }) }).then(rows),
            canReports() ? R.owed().catch(function () { return null; }) : Promise.resolve(null)
          ]).then(function (q) {
            var by = {}, rep = {};
            (q[0] || []).forEach(function (x) { by[x.engagement_id] = x; });
            (q[1] || []).forEach(function (x) { if (x.client_id && !x.brand) rep[x.client_id] = x; });
            var REP = { published: ['Published', 'ok'], confirmed: ['Confirmed', 'warn'], review: ['In review', 'warn'], draft: ['Draft', 'warn'], none: ['Not started', 'off'] };
            var list = eng.map(function (e) {
              var c = by[e.id] || {};
              return { e: e, live: Number(c.live) || 0, done: Number(c.done) || 0, late: Number(c.late) || 0, rep: rep[e.client_id] };
            }).sort(function (a, b) {
              return (b.late > 0) - (a.late > 0) || (a.live ? a.done / a.live : 1) - (b.live ? b.done / b.live : 1) || String(a.e.clients.name).localeCompare(String(b.e.clients.name));
            });
            var A = window.ADspaceAdmin, now = Date.now(), SHOWN = 8, more = Math.max(0, list.length - SHOWN);
            body.innerHTML = '<div class="ovw-tr ovw-th is-cmonth"><span>Client</span><span>Posts</span><span class="ovw-hide-n">Report</span><span class="ovw-hide-n">Meeting</span></div>' +
              list.map(function (m, i) {
                var tone = m.late ? 'danger' : m.live && m.done === m.live ? 'ok' : 'warn', r = m.rep && REP[m.rep.status];
                var meet = m.e.meeting_na ? 'Not needed' : m.e.meeting_at ? (Date.parse(m.e.meeting_at) < now ? 'Held ' : '') + CK.date(m.e.meeting_at, { year: false }) : 'Not set';
                /* On a narrow pane the report and the meeting read as a line
                   under the name, never dropped (the 4-step pass, 2026-11-13). */
                var sub = (r ? 'Report ' + (r[0] === 'Draft' ? 'in draft' : r[0].toLowerCase()) + ' · ' : '') + 'Meeting ' + meet.charAt(0).toLowerCase() + meet.slice(1);
                return '<button class="ovw-tr is-cmonth" type="button"' + (i >= SHOWN ? ' hidden' : '') + ' data-go="/admin/?s=work&view=months&wc=' + esc(encodeURIComponent(m.e.client_id)) + '">' +
                  '<span class="ovw-who">' + (A && A.clientMark ? A.clientMark(m.e.clients, m.e.client_id) : '') + '<span class="ovw-who-t"><b>' + esc(m.e.clients.name) + '</b><small class="ovw-show-n">' + esc(sub) + '</small></span></span>' +
                  /* Done green, late red, open grey on one bar (phase 4). */
                  '<span class="ovw-cprog"><span class="ovw-pbar is-month" aria-hidden="true">' + (m.live ? '<i class="is-done" style="width:' + (m.done / m.live * 100).toFixed(1) + '%"></i>' +
                    (m.late ? '<i class="is-late" style="width:' + (Math.min(m.late, m.live - m.done) / m.live * 100).toFixed(1) + '%"></i>' : '') : '') + '</span>' +
                    '<small' + (m.late ? ' class="is-late"' : '') + '>' + (m.live ? m.done + ' of ' + m.live : 'No tasks') + (m.late ? ' · ' + m.late + ' late' : '') + '</small></span>' +
                  '<span class="ovw-hide-n">' + (r ? '<span class="chip-state is-' + r[1] + '">' + r[0] + '</span>' : '<span class="muted">—</span>') + '</span>' +
                  '<span class="ovw-hide-n ovw-meet">' + esc(meet) + '</span></button>';
              }).join('') +
              (more ? '<button class="btn btn-sm ovw-more" type="button" aria-expanded="false"><span>Show ' + more + ' more</span>' + DOWN + '</button>' : '');
            Array.prototype.forEach.call(body.querySelectorAll('[data-go]'), function (b) {
              b.addEventListener('click', function () { go(b.getAttribute('data-go'), 'work'); });
            });
            var mb = body.querySelector('.ovw-more');
            if (mb) mb.addEventListener('click', function () {
              var open = mb.getAttribute('aria-expanded') !== 'true';
              var rs = Array.prototype.slice.call(body.querySelectorAll('button.ovw-tr')).slice(SHOWN);
              rs.forEach(function (b) { b.hidden = !open; });
              mb.setAttribute('aria-expanded', String(open));
              mb.firstChild.textContent = open ? 'Show fewer' : 'Show ' + more + ' more';
              if (open && rs[0]) rs[0].focus();
            });
          });
        }).catch(function (e) { fail(body, 'Clients this month', e, run); });
      };
      run();
    }
    return { people: people, clients: clients, stages: stages };
  })();

  function redraw() { build(true); }
  var ME = (function () {
    var memo = null;
    function read() {
      if (memo) return memo;
      var O = window.ADspaceOps;
      memo = O && O.mine ? O.mine() : Promise.resolve({ tasks: [], waiting: [], failed: [] });
      return memo;
    }
    /* The leads the colleague sells (Sales by is them), read once a visit
       where they may see leads; a lead past its follow-up time joins Today. */
    var leadMemo = null;
    function myLeads() {
      var me = bridge.me && bridge.me();
      if (!me || !may('clients.leads', 'view')) return Promise.resolve([]);
      /* Every read is made inside its promise, so one the client cannot
         build is a refusal said on the page, never a thrown page. */
      if (!leadMemo) leadMemo = Promise.resolve().then(function () {
        return db.from('clients').select('id, name, slug, stage, stage_since, logo_url')
          .eq('sales_by', me.id).in('stage', ['lead', 'contacted', 'proposal', 'active']);
      }).then(rows);
      return leadMemo;
    }
    function staleOf(c) {
      var CRM = window.ADspaceCRM, lim = CRM && CRM.staleH ? CRM.staleH(c)[c.stage] : null, t = Date.parse(c.stage_since);
      if (!lim || isNaN(t)) return 0;
      var h = (Date.now() - t) / 36e5 - lim;
      return h >= 0 ? Math.max(1, Math.floor(h / 24)) : 0;
    }
    function leads() {
      return myLeads().then(function (list) {
        return (list || []).filter(function (c) { return c.stage !== 'active' && staleOf(c); }).map(function (c) {
          var over = staleOf(c);
          return { kind: 'lead', title: c.name, meta: [c.stage === 'lead' ? 'Lead' : 'Proposal sent', 'Follow-up'], late: true,
            lateWord: over + (over === 1 ? ' day overdue' : ' days overdue'), sec: 'clients', url: clientUrl(c, 'calls'), go: 'clients', act: 'Open' };
        });
      });
    }
    /* Reports the colleague submitted that are published and not sent. */
    function unsent() {
      var me = bridge.me && bridge.me(), SM = window.ADspaceSmReport;
      if (!me || !may('reports', 'view')) return Promise.resolve([]);
      return Promise.resolve().then(function () {
        return db.from('sm_reports').select('id, kind, period_start, period_end, brand_name, client_id, clients(name)')
          .eq('status', 'published').is('sent_on', null).eq('submitted_by', me.id);
      }).then(rows).then(function (list) {
          return (list || []).map(function (r) {
            return { kind: 'report', title: (r.kind === 'ads' ? 'Advertising Report' : 'Accounts Report') + ' · ' + (SM && SM.periodWord ? SM.periodWord(r.period_start, r.period_end) : r.period_start),
              meta: [r.brand_name || (r.clients && r.clients.name) || '', 'Published, not sent'], sec: 'reports',
              url: '/admin/?s=reports&report=' + encodeURIComponent(r.id), go: 'reports', act: 'Open' };
          });
        });
    }
    function dayWord(d) { return CK.date(d, { weekday: true, year: false }); }
    /* The four figures: open, late, due this week and what waits on you. */
    function tiles(box) {
      var grid = document.createElement('div');
      grid.className = 'ovw-kpis ovw-lead';
      grid.id = 'ovwMeLead';
      box.appendChild(grid);
      /* A figure whose read failed says so with Try again, never 0 (the
         review, 2026-11-13). */
      var get = function (f, src) {
        return function () {
          return read().then(function (d) {
            var bad = d.failed.filter(function (x) { return src === 'tasks' ? x === 'Tasks' : x !== 'Tasks'; });
            if (bad.length) throw new Error('Could not load ' + bad.join(', ') + '.');
            return f(d);
          });
        };
      };
      /* A colleague who sells and holds no My Work (Sales) reads their
         leads' figures in its place. */
      if (!may('ops', 'view')) {
        if (!may('clients.leads', 'view')) { grid.remove(); return; }
        var lg = function (f) { return function () { return myLeads().then(f); }; };
        var monthStart = CK.today().slice(0, 7) + '-01';
        [{ key: 'me-leads', title: 'My leads', sec: 'clients', load: lg(function (l) {
            var open = l.filter(function (c) { return c.stage !== 'active'; });
            var prop = open.filter(function (c) { return c.stage === 'proposal'; }).length;
            return { fig: String(open.length), sub: prop ? prop + ' proposal' + (prop === 1 ? '' : 's') + ' sent' : 'No proposals sent' };
          }) },
         { key: 'me-follow', title: 'Overdue follow-ups', sec: 'clients', load: lg(function (l) {
            var late = l.filter(function (c) { return c.stage !== 'active' && staleOf(c); });
            var oldest = late.reduce(function (m, c) { return Math.max(m, staleOf(c)); }, 0);
            return { fig: String(late.length), tone: late.length ? 'err' : '', sub: late.length ? 'Oldest ' + daysWord(oldest) + ' overdue' : 'None overdue' };
          }) },
         { key: 'me-contacted', title: 'Contacted', sec: 'clients', load: lg(function (l) {
            return { fig: String(l.filter(function (c) { return c.stage === 'contacted'; }).length), sub: 'Awaiting a proposal' };
          }) },
         { key: 'me-won', title: 'Won this month', sec: 'clients', load: lg(function (l) {
            var n = l.filter(function (c) { return c.stage === 'active' && CK.day(c.stage_since) >= monthStart; }).length;
            return { fig: String(n), sub: n ? 'Active since ' + CK.month(monthStart) : 'None this month' };
          }) }].forEach(function (t) { tile(grid, t); });
        return;
      }
      [{ key: 'me-open', title: 'My open tasks', sec: 'work', load: get(function (d) {
          var week = d.tasks.filter(function (t) { return t.days !== null && t.days >= 0 && t.days <= 7 && !t.late; }).length;
          return { fig: String(d.tasks.length), sub: week ? week + ' due within 7 days' : 'None due within 7 days' };
        }, 'tasks') },
       { key: 'me-late', title: 'Late', sec: 'work', load: get(function (d) {
          var late = d.tasks.filter(function (t) { return t.late; });
          var oldest = late.reduce(function (m, t) { return Math.max(m, t.lateDays || 0); }, 0);
          return { fig: String(late.length), tone: late.length ? 'err' : '', sub: late.length ? (oldest ? 'Oldest ' + daysWord(oldest) : 'Late today') : 'None late' };
        }, 'tasks') },
       { key: 'me-today', title: 'Due today', sec: 'work', load: get(function (d) {
          var n = d.tasks.filter(function (t) { return t.days === 0 && !t.late; }).length;
          var next = d.tasks.filter(function (t) { return t.days !== null && t.days > 0; }).sort(function (a, b) { return a.days - b.days; })[0];
          return { fig: String(n), sub: next ? 'Next ' + dayWord(next.due) : 'Nothing further due' };
        }, 'tasks') },
       { key: 'me-wait', title: 'Waiting for you', sec: 'work', load: get(function (d) {
          var by = {};
          d.waiting.forEach(function (r) { by[r.state] = (by[r.state] || 0) + 1; });
          var parts = Object.keys(by).map(function (k) { return by[k] + ' ' + k.toLowerCase(); });
          return { fig: String(d.waiting.length), sub: parts.length ? parts.slice(0, 2).join(', ') : 'Nothing waiting' };
        }, 'wait') }].forEach(function (t) { tile(grid, t); });
    }
    /* The Assistant as one field (Ctrl + J): what is typed opens it with the
       question asked; two suggested questions under it. */
    function ask(box, d) {
      var AG = window.ADspaceAgent;
      if (!AG || !AG.ask || !$('agentOpen') || $('agentOpen').hidden) return;
      var wrap = document.createElement('div');
      wrap.className = 'ovw-ask';
      wrap.innerHTML = '<form class="ovw-ask-box" id="ovwAsk"><span class="ovw-ask-ai" aria-hidden="true">' +
        ((window.ADspaceConfirm && window.ADspaceConfirm.ai && window.ADspaceConfirm.ai.glyph) || '') + '</span>' +
        '<input class="ovw-ask-field" id="ovwAskQ" type="text" autocomplete="off" aria-label="Ask about your clients and work" placeholder="Ask about your clients and work">' +
        '<kbd class="ovw-ask-key">Ctrl J</kbd></form><div class="ovw-ask-try" id="ovwAskTry"></div>';
      box.appendChild(wrap);
      wrap.querySelector('form').addEventListener('submit', function (e) {
        e.preventDefault();
        var q = $('ovwAskQ').value.trim();
        if (!q) { AG.open(); return; }
        $('ovwAskQ').value = '';
        AG.ask(q);
      });
      var late = d.tasks.filter(function (t) { return t.late; }).length, qs = [];
      if (late) qs.push(late === 1 ? 'Which of my tasks is late?' : 'Which of my ' + late + ' late tasks comes first?');
      if (may('ops', 'view')) qs.push('What is due this week?');
      if (may('clients.leads', 'view')) qs.push('Which of my leads need a follow-up?');
      var c = d.tasks.filter(function (t) { return t.client; })[0];
      if (c) qs.push('Summarise ' + c.client + '’s month');
      var tr = wrap.querySelector('#ovwAskTry');
      tr.innerHTML = qs.slice(0, 2).map(function (q) { return '<button class="ovw-ask-q" type="button">' + esc(q) + '</button>'; }).join('');
      tr.addEventListener('click', function (e) {
        var b = e.target.closest('.ovw-ask-q');
        if (b) AG.ask(b.textContent);
      });
    }
    /* Today: one list of what needs the colleague, late first, then what
       waits on their decision, then what is due today; each row its act. */
    function today(col, d, extra) {
      var card = document.createElement('section');
      card.className = 'chartcard ovw-card ovw-today';
      card.id = 'ovwToday';
      col.appendChild(card);
      var items = [];
      d.tasks.forEach(function (t) {
        if (!t.late && t.days !== 0 && !t.urgent) return;
        items.push({ group: t.late || t.urgent ? 'late' : 'today', kind: 'task', title: t.code ? t.code + ' ' + t.name : t.name,
          meta: [t.client || 'Internal', t.stage], late: t.late, lateWord: t.late ? t.lateWord : t.urgent ? 'Urgent delivery' : t.deadline,
          sec: 'work', url: '/admin/?s=work&open=' + encodeURIComponent(t.id), go: 'work', act: 'Open', ring: ringOf(t) });
      });
      extra.forEach(function (x) { x.group = x.late ? 'late' : 'today'; items.push(x); });
      /* What waits on the colleague's decision is its own card under Today
         (Waiting for you, drawn by My Work's own script), never a row here. */
      var KINDS = [['all', 'All'], ['task', 'Tasks'], ['lead', 'Leads'], ['report', 'Reports']];
      var on = 'all';
      var paint = function () {
        var list = items.filter(function (x) { return on === 'all' || x.kind === on; });
        var kinds = KINDS.filter(function (k) { return k[0] === 'all' || items.some(function (x) { return x.kind === k[0]; }); });
        var head = '<div class="chart-head"><h3 class="chart-title">Today</h3><span class="ovw-today-n">' +
          (items.length ? items.length + (items.length === 1 ? ' item' : ' items') : '') + '</span></div>';
        if (!items.length) {
          card.innerHTML = head;
          var b = document.createElement('div');
          card.appendChild(b);
          /* A failed read is never drawn as nothing to do. */
          if (d.failed.length) UI.failLine(b, d.failed.join(', '), 'The data could not be loaded.', redraw);
          else UI.emptyLine(b, 'Nothing needs you today.');
          return;
        }
        var chips = kinds.length > 2 ? '<div class="ovw-today-chips" role="group" aria-label="Show">' + kinds.map(function (k) {
          var n = k[0] === 'all' ? items.length : items.filter(function (x) { return x.kind === k[0]; }).length;
          return '<button class="ovw-chip' + (k[0] === on ? ' is-on' : '') + '" type="button" data-k="' + k[0] + '" aria-pressed="' + (k[0] === on) + '">' +
            esc(k[1]) + ' <b>' + n + '</b></button>';
        }).join('') + '</div>' : '';
        var GROUPS = [['late', 'Late'], ['today', 'Due today']];
        var html = GROUPS.map(function (g) {
          var rs = list.filter(function (x) { return x.group === g[0]; });
          if (!rs.length) return '';
          return '<h4 class="ovw-today-h' + (g[0] === 'late' ? ' is-late' : '') + '">' + g[1] + '</h4>' + rs.map(function (x) {
            var i = items.indexOf(x), mark = x.ring || (bridge.glyph ? bridge.glyph(x.sec) : '');
            var acts = '<button class="btn btn-sm" type="button" data-a="open">' + esc(x.act || 'Open') + '</button>';
            return '<div class="ovw-today-row" data-i="' + i + '"><span class="ovw-today-tile' + (x.ring ? ' has-ring' : '') + '">' + mark + '</span>' +
              '<button class="ovw-today-what" type="button" data-a="open"><b>' + esc(x.title) + '</b><small>' +
                x.meta.filter(Boolean).map(function (m) { return '<span class="nb">' + esc(m) + '</span>'; }).join(' · ') +
                (x.lateWord ? ' · <span class="nb' + (x.late || x.lateWord === 'Urgent delivery' ? ' is-late' : '') + '">' + esc(x.lateWord) + '</span>' : '') + '</small></button>' +
              '<span class="ovw-today-acts">' + acts + '</span></div>';
          }).join('');
        }).join('');
        card.innerHTML = head + chips + '<div class="ovw-today-list">' + (html || '<p class="emptyline">No entries.</p>') + '</div>' +
          (d.failed.length ? '<div class="errline"><b>Could not load ' + esc(d.failed.join(', ')) + '.</b>' +
            '<button class="btn btn-sm" type="button" data-a="retry">Try again</button></div>' : '');
      };
      card.addEventListener('click', function (e) {
        var chip = e.target.closest('.ovw-chip');
        if (chip) { on = chip.getAttribute('data-k'); paint(); return; }
        var b = e.target.closest('[data-a]'), row = e.target.closest('.ovw-today-row');
        if (b && b.getAttribute('data-a') === 'retry') { redraw(); return; }
        if (!b || !row) return;
        var x = items[Number(row.getAttribute('data-i'))];
        if (!x) return;
        var a = b.getAttribute('data-a');
        if (a === 'open') {
          if (x.open) { x.open(); return; }
          go(x.url, x.go || x.sec);
          return;
        }
      });
      paint();
    }
    /* The next five working days: the colleague's tasks by their due date,
       and the client meetings they lead. */
    function week(col, d) {
      var me = bridge.me && bridge.me();
      var card = document.createElement('section');
      card.className = 'chartcard ovw-card ovw-week';
      card.id = 'ovwWeek';
      card.innerHTML = '<div class="chart-head"><h3 class="chart-title">Next 5 days</h3><span class="ovw-today-n"></span></div><div class="ovw-days"></div>';
      col.appendChild(card);
      var days = [], dd = CK.today();
      while (days.length < 5) { var wd = CK.weekday(dd); if (wd !== 0 && wd !== 6) days.push(dd); dd = CK.addDays(dd, 1); }
      card.querySelector('.ovw-today-n').textContent = CK.date(days[0], { year: false }) + ' to ' + CK.date(days[4], { year: false });
      var meet = may('ops', 'view') && me ? Promise.resolve().then(function () { return db.from('ops_engagements').select('id, meeting_at, meeting_channel, clients(name)')
        .eq('meeting_owner_id', me.id).gte('meeting_at', new Date(days[0] + 'T00:00:00+08:00').toISOString())
        .lte('meeting_at', new Date(days[4] + 'T23:59:59+08:00').toISOString()); }).then(rows).catch(function () { return null; }) : Promise.resolve([]);
      meet.then(function (ms) {
        var html = days.map(function (day, i) {
          var ts = d.tasks.filter(function (t) { return t.due && CK.day(t.due) === day && !(i === 0 && t.late); }).map(function (t) {
            var rg = ringOf(t);
            return '<span class="ovw-ev' + (t.late ? ' is-late' : '') + (rg ? ' has-ring' : '') + '">' + rg + '<span class="ovw-ev-t">' + esc(t.code || t.name) + (t.code ? ' ' + esc(t.name) : '') + '</span></span>';
          });
          (ms || []).forEach(function (m) {
            if (CK.day(m.meeting_at) !== day) return;
            ts.push('<span class="ovw-ev is-meet">' + esc(CK.clock(m.meeting_at, { space: false })) + ' · ' + esc((m.clients && m.clients.name) || 'Meeting') + '</span>');
          });
          var wdw = CK.date(day, { weekday: true }).split(',')[0];
          return '<div class="ovw-day' + (i === 0 ? ' is-today' : '') + '"><span class="ovw-day-d">' + esc(wdw) + '<b>' + Number(day.slice(8, 10)) + '</b></span>' +
            '<div class="ovw-day-evs">' + (ts.length ? ts.slice(0, 4).join('') + (ts.length > 4 ? '<span class="ovw-ev is-more">' + (ts.length - 4) + ' more</span>' : '') : '<span class="ovw-ev is-none">Nothing due</span>') + '</div></div>';
        }).join('');
        card.querySelector('.ovw-days').innerHTML = html;
        /* A refused read of the meetings is said, never drawn as a free day. */
        if (ms === null) {
          var f = document.createElement('div');
          f.className = 'errline';
          f.innerHTML = '<b>Could not load the meetings.</b><button class="btn btn-sm" type="button">Try again</button>';
          f.querySelector('button').addEventListener('click', redraw);
          card.appendChild(f);
        }
      });
    }
    /* My clients this month: the clients the colleague is person in charge
       of whose month is this month, done of all and late. */
    function clients(col) {
      var me = bridge.me && bridge.me();
      if (!me || !may('ops', 'view') || !me.name) return;
      var card = document.createElement('section');
      card.className = 'chartcard ovw-card ovw-mycl';
      card.id = 'ovwMyClients';
      card.innerHTML = '<div class="chart-head"><h3 class="chart-title">My clients this month</h3></div><div class="ovw-mycl-list"></div>';
      col.appendChild(card);
      var host = card.querySelector('.ovw-mycl-list');
      var run = function () {
        UI.skeleton(host, 2);
        Promise.resolve().then(function () {
          return db.from('ops_engagements').select('id, client_id, status, clients!inner(name, slug, owner, stage)').eq('period', CK.today().slice(0, 7))
            .eq('clients.owner', me.name);
        }).then(rows).then(function (eng) {
            eng = (eng || []).filter(function (e) { return e.status !== 'cancelled'; });
            if (!eng.length) { card.remove(); return; }
            return db.rpc('ops_engagement_counts', { p_engagements: eng.map(function (e) { return e.id; }) }).then(rows).then(function (cs) {
              var by = {};
              (cs || []).forEach(function (x) { by[x.engagement_id] = x; });
              host.innerHTML = eng.map(function (e) {
                var c = by[e.id] || {}, live = Number(c.live) || 0, done = Number(c.done) || 0, late = Number(c.late) || 0;
                var pd = live ? done / live * 100 : 0, pl = live ? Math.min(late, live - done) / live * 100 : 0;
                return '<button class="ovw-mycl-row" type="button" data-go="/admin/?s=work&view=months&wc=' + esc(encodeURIComponent(e.client_id)) + '">' +
                  '<span class="ovw-mycl-top"><b>' + esc(e.clients.name) + '</b><small>' + (live ? done + ' of ' + live + ' done' : 'No tasks') +
                  (late ? ' · <span class="is-late">' + late + ' late</span>' : '') + '</small></span>' +
                  '<span class="ovw-mycl-bar" aria-hidden="true"><i class="is-done" style="width:' + pd.toFixed(1) + '%"></i><i class="is-late" style="width:' + pl.toFixed(1) + '%"></i></span></button>';
              }).join('');
              Array.prototype.forEach.call(host.querySelectorAll('[data-go]'), function (b) {
                b.addEventListener('click', function () { go(b.getAttribute('data-go'), 'work'); });
              });
            });
          }).catch(function (e) { fail(host, 'My clients this month', e, run); });
      };
      run();
    }
    function build(box) {
      memo = null;
      leadMemo = null;
      tiles(box);
      var wrap = document.createElement('div');
      wrap.className = 'ovw-ask-host';
      box.appendChild(wrap);
      var cols = document.createElement('div');
      cols.className = 'ovw-me-cols';
      var left = document.createElement('div'), right = document.createElement('div');
      left.className = 'ovw-me-main'; right.className = 'ovw-me-side';
      cols.appendChild(left); cols.appendChild(right);
      box.appendChild(cols);
      var todayHost = document.createElement('div');
      todayHost.className = 'ovw-me-today';
      left.appendChild(todayHost);
      /* Waiting for you, painted into this host by My Work's own script
         (`paintWaiting`): its Approve, Decline and Remind as they were. */
      var wait = document.createElement('div');
      wait.id = 'workWaiting';
      wait.setAttribute('data-narrow', '860');
      wait.hidden = true;
      left.appendChild(wait);
      var waitMsg = document.createElement('p');
      waitMsg.id = 'ovwWaitMsg';
      waitMsg.className = 'msg';
      waitMsg.setAttribute('aria-live', 'polite');
      left.appendChild(waitMsg);
      UI.skeleton(todayHost, 4);
      var lost = [];
      var named = function (p, word) { return p.catch(function () { lost.push(word); return []; }); };
      Promise.all([read(), named(leads(), 'Leads'), named(unsent(), 'Reports')]).then(function (r) {
        var d = { tasks: r[0].tasks, waiting: r[0].waiting, failed: r[0].failed.concat(lost) };
        ask(wrap, d);
        if (!wrap.children.length) wrap.remove();
        todayHost.innerHTML = '';
        today(todayHost, d, r[1].concat(r[2]));
        if (may('ops', 'view')) week(right, d);
        clients(right);
        if (!right.children.length) cols.classList.add('is-one');
        if (window.ADspaceAdmin && window.ADspaceAdmin.counts && may('ops', 'view')) {
          var late = d.tasks.filter(function (t) { return t.late; }).length;
          window.ADspaceAdmin.counts('overview', [[d.tasks.length, d.tasks.length === 1 ? 'open task' : 'open tasks'], late ? [late, 'late', 'late'] : null]);
        }
      }).catch(function (e) { fail(todayHost, 'Today', e, redraw); });
    }
    return { build: build };
  })();

  function build(keep) {
    var box = $('ovwBody');
    if (!box) return;
    var y = keep ? window.scrollY : 0;
    box.innerHTML = '';
    bar(box);
    greet();
    if (page === 'me') {
      ME.build(box);
    } else {
      lead(box);
      /* The line under the Dashboard's name: the open work and what of it
         is late, from the report the page already reads. */
      if (canFigures() && window.ADspaceAdmin && window.ADspaceAdmin.counts) {
        R.report().then(function (d) {
          var open = (d.running || []).reduce(function (n, r) { return n + (Number(r.count) || 0); }, 0), late = (d.late || []).length;
          window.ADspaceAdmin.counts('overview', [[open, 'open tasks'], late ? [late, 'late', 'late'] : null]);
        }).catch(function () {});
      }
      /* Team (the revamp, phase 2, 2026-11-13): People beside the on-time
         trend, then Clients this month beside Needs attention, each pair
         on the golden proportion; one over the other in a narrow pane. */
      var pairOf = function (fill) {
        var pr = document.createElement('div');
        pr.className = 'ovw-pair';
        box.appendChild(pr);
        fill(pr);
        if (!pr.children.length) pr.remove();
        else if (pr.children.length === 1) pr.classList.add('is-one');
      };
      TEAM.stages(box);
      pairOf(function (pr) {
        TEAM.people(pr);
        var ontime = PAGE1[0].filter(function (c) { return c.key === 'ontime' && c.can(); })[0];
        if (ontime) chart(pr, ontime);
      });
      pairOf(function (pr) { TEAM.clients(pr); list(pr); });
    }
    if (keep) window.scrollTo(0, y);
    if (keep && $('ovwPeriod')) $('ovwPeriod').focus({ preventScroll: true });
  }
  function urlState() {
    return { p: page !== 'me' && period !== 'month' ? period : '', pg: page === 'summary' ? 'team' : '' };
  }
  /* The page reopens on the tab last used (the user's choice, 2026-11-13):
     kept in this browser, the address winning. */
  var PAGE_KEY = 'adspace-dash-page';
  function keepPage() { try { localStorage.setItem(PAGE_KEY, page); } catch (e) { /* nothing kept */ } }
  function keptPage() { try { return localStorage.getItem(PAGE_KEY) || ''; } catch (e) { return ''; } }

  function enter() {
    var box = $('ovwBody');
    if (!box) return;
    memo = {};
    var want = new URLSearchParams(location.search).get('p');
    period = PERIODS.some(function (p) { return p[0] === want; }) ? want : 'month';
    var pg = new URLSearchParams(location.search).get('pg') || keptPage();
    /* Team detail moved to Analytics (2026-11-13): an old address opens Team. */
    page = (pg === 'team' || pg === 'summary' || pg === 'detail') ? 'summary' : 'me';
    /* A page this colleague is not offered falls back to Me, which every
       colleague holds. */
    if (!pagesShown().some(function (p) { return p[0] === page; })) page = 'me';
    build(false);
    if (bridge.setUrl) bridge.setUrl();
  }

  /* The greeting follows the clock while the Dashboard is on screen, a
     minute at a time; it reads nothing (the review, 2026-11-13). */
  setInterval(function () {
    var sec = $('sectionOverview');
    if (sec && !sec.hidden && !document.hidden) greet();
  }, 60000);
  window.ADspaceOverview = { enter: enter, urlState: urlState, any: any, greetWord: greetWord,
    groupCan: groupCan, forAnalytics: forAnalytics, focusCard: focusCard };
  if (bridge.overviewReady) bridge.overviewReady();
})();
