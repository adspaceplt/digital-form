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

  var MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
  var LONG = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
              'September', 'October', 'November', 'December'];
  function dayStart(d) { var x = new Date(d); x.setHours(0, 0, 0, 0); return x; }
  function today() { return dayStart(new Date()); }
  // Whole days from a date to today; a future date is 0.
  function daysSince(v) {
    if (!v) return 0;
    var d = dayStart(String(v).length === 10 ? v + 'T00:00:00' : v);
    return isNaN(d.getTime()) ? 0 : Math.max(0, Math.round((today() - d) / 86400000));
  }
  var RESTRICT_WORD = { instagram: 'Instagram', facebook: 'Facebook', tiktok: 'TikTok', xhs: 'rednote', other: 'Other account' };
  function daysWord(n) { return n === 1 ? '1 day' : n + ' days'; }
  function sinceWord(v) { var n = daysSince(v); return n ? daysWord(n) : 'Today'; }
  function dateWord(v) {
    var d = new Date(String(v).length === 10 ? v + 'T00:00:00' : v);
    return isNaN(d.getTime()) ? '' : d.getDate() + ' ' + MON[d.getMonth()] + ' ' + d.getFullYear();
  }
  // A date in this year without its year: "7 Oct"; another year keeps it.
  function shortDate(v) {
    var d = new Date(String(v).length === 10 ? v + 'T00:00:00' : v);
    if (isNaN(d.getTime())) return '';
    return d.getFullYear() === new Date().getFullYear() ? d.getDate() + ' ' + MON[d.getMonth()] : dateWord(v);
  }
  // Last month: its first day, its last day, its name and its address key.
  function lastMonth() {
    var now = new Date();
    var a = new Date(now.getFullYear(), now.getMonth() - 1, 1), z = new Date(now.getFullYear(), now.getMonth(), 0);
    return { start: a, end: z, word: LONG[a.getMonth()] + ' ' + a.getFullYear(), short: MON[a.getMonth()],
             key: a.getFullYear() + '-' + String(a.getMonth() + 1).padStart(2, '0') };
  }
  function isoDay(d) {
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  }
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
  function addMonths(d, n) {
    var x = new Date(d.getFullYear(), d.getMonth() + n, 1, d.getHours(), d.getMinutes(), d.getSeconds());
    var last = new Date(x.getFullYear(), x.getMonth() + 1, 0).getDate();
    x.setDate(Math.min(d.getDate(), last));
    return x;
  }
  function rangeOf(p) {
    var now = new Date(), m0 = new Date(now.getFullYear(), now.getMonth(), 1);
    if (p === 'last') return { from: new Date(m0.getFullYear(), m0.getMonth() - 1, 1), to: m0 };
    var q0 = new Date(now.getFullYear(), Math.floor(now.getMonth() / 3) * 3, 1);
    if (p === 'quarter') return { from: q0, to: now };
    if (p === 'lastq') return { from: new Date(q0.getFullYear(), q0.getMonth() - 3, 1), to: q0 };
    if (p === 'year') return { from: new Date(now.getFullYear(), 0, 1), to: now };
    return { from: m0, to: now };
  }
  function prevOf(p) {
    var r = rangeOf(p), n = p === 'quarter' || p === 'lastq' ? 3 : p === 'year' ? 12 : 1;
    return { from: addMonths(r.from, -n), to: addMonths(r.to, -n) };
  }
  function quarterWord(d) { return 'Q' + (Math.floor(d.getMonth() / 3) + 1) + ' ' + d.getFullYear(); }
  // What a change is measured against, in a word: "on Sept", "on last quarter".
  function prevWord(p) {
    if (p === 'quarter') return 'last quarter';
    if (p === 'lastq') return quarterWord(prevOf(p).from);
    if (p === 'year') return 'last year';
    return MON[prevOf(p).from.getMonth()];
  }
  // The period in words: "1 to 12 Oct 2026", "Sept 2026", "1 Jul to 12 Oct 2026".
  function spanWord(r) {
    var a = r.from, b = new Date(r.to.getTime() - 1);
    var whole = a.getDate() === 1 && r.to.getDate() === 1 && r.to.getHours() === 0 && r.to.getMinutes() === 0;
    if (whole && a.getMonth() === b.getMonth()) return MON[a.getMonth()] + ' ' + a.getFullYear();
    if (a.getMonth() === b.getMonth()) return a.getDate() + ' to ' + b.getDate() + ' ' + MON[a.getMonth()] + ' ' + a.getFullYear();
    return a.getDate() + ' ' + MON[a.getMonth()] + ' to ' + b.getDate() + ' ' + MON[b.getMonth()] + ' ' + b.getFullYear();
  }
  function periodName(p) {
    return p === 'last' ? MON[rangeOf('last').from.getMonth()] : p === 'quarter' ? 'this quarter'
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
  function report(r) {
    return db.rpc('ops_report', { p_from: r.from.toISOString(), p_to: r.to.toISOString() }).then(rows);
  }
  var R = {
    report: function () { return once('rep:' + period, function () { return report(rangeOf(period)); }); },
    reportPrev: function () { return once('prev:' + period, function () { return report(prevOf(period)); }); },
    /* Six months, one call a month, for the on-time line and what was
       delivered each month. */
    months: function () {
      return once('rep6', function () {
        var ms = CH.months(6);
        return Promise.all(ms.map(function (m) { return report({ from: m.start, to: m.end }); }))
          .then(function (all) { return ms.map(function (m, i) { return { m: m, d: all[i] || {} }; }); });
      });
    },
    /* Every client the group reads, once: the sales figures, leads going
       cold, the pipeline and restricted accounts all draw from it. */
    clients: function () {
      return once('clients', function () {
        return db.from('clients').select('id, name, slug, stage, stage_reason, stage_log, stage_since, created_at, source, owner, market, ' +
          'restricted_platform, restricted_since, restricted_note').then(rows).then(function (l) { return l || []; });
      });
    },
    lines: function () {
      return once('lines', function () {
        return db.from('client_services').select('client_id, qty, rate, tenure, term_adjust, term_pct, state, archived_at')
          .then(rows).then(function (l) { return l || []; });
      });
    },
    openTasks: function () {
      return once('open', function () {
        return db.from('ops_tasks').select('id, task_no, title, current_final_due_at, client_id, clients(name, stage)')
          .is('completed_at', null).is('cancelled_at', null).is('archived_at', null).then(rows).then(function (l) { return l || []; });
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
        return db.from('batches').select('id, title, client_id, published_at, created_at, clients(id, name, slug, owner)')
          .eq('published', true).order('created_at', { ascending: false }).limit(200).then(rows).then(function (sets) {
            sets = sets || [];
            if (!sets.length) return [];
            return db.from('posts').select('*').in('batch_id', sets.map(function (s) { return s.id; })).then(rows).then(function (posts) {
              posts = posts || [];
              var pids = posts.map(function (p) { return p.id; });
              var reviews = pids.length
                ? db.from('reviews').select('*').in('post_id', pids).order('created_at', { ascending: false }).then(rows)
                : Promise.resolve([]);
              return reviews.then(function (revs) {
                var latest = {}, reset = {}, round = {};
                posts.forEach(function (p) { reset[p.id] = p.review_reset_at; round[p.id] = p.round || 1; });
                (revs || []).forEach(function (r) {
                  if (latest[r.post_id] || r.undone_at) return;
                  if ((r.round || 1) !== round[r.post_id]) return;
                  if (reset[r.post_id] && new Date(r.created_at) < new Date(reset[r.post_id])) return;
                  latest[r.post_id] = r;
                });
                return sets.map(function (s) {
                  var mine = posts.filter(function (p) { return p.batch_id === s.id; });
                  var ok = 0, ch = 0;
                  mine.forEach(function (p) {
                    var d = latest[p.id];
                    if (d && d.decision === 'approved') ok++; else if (d) ch++;
                  });
                  return { s: s, n: mine.length, ok: ok, ch: ch };
                }).filter(function (x) { return x.n && x.ok < x.n; });
              });
            });
          });
      });
    },
    noSet: function () {
      return once('noset', function () {
        var first = new Date(); first = new Date(first.getFullYear(), first.getMonth(), 1);
        return Promise.all([
          db.from('clients').select('id, name, slug, owner').eq('stage', 'active').eq('review_hidden', false).order('name').then(rows),
          db.from('batches').select('client_id, created_at').order('created_at', { ascending: false }).then(rows)
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
          .select('id, state, visit_date, submission_due, submitted_at, campaign_id, campaigns(id, title, owner), creators(name)')
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
  function figuresFor(r, lines) {
    return R.clients().then(function (cl) { return S().figures(cl, lines || null, r); });
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
    { key: 'late', title: 'Late tasks', can: canFigures, load: function () {
      return R.report().then(function (d) {
        return (d.late || []).map(function (t) {
          return { name: taskName(t), meta: t.client || 'Internal', tag: 'Task', who: t.owner || 'Unassigned',
                   late: true, days: Number(t.days_over) || 0, since: overWord(t),
                   url: '/admin/?s=work&open=' + encodeURIComponent(t.task_id), section: 'work' };
        });
      });
    } },
    /* A client paused or ended still owes its revisions and reviews. */
    { key: 'urgent', title: 'Open work for paused and past clients', can: function () { return may('ops', 'manage') && may('ops.all'); }, load: function () {
      return R.openTasks().then(function (list) {
        return list.filter(function (t) { var st = t.clients && t.clients.stage; return st === 'paused' || st === 'past'; }).map(function (t) {
          var n = t.current_final_due_at ? Math.floor((Date.now() - new Date(t.current_final_due_at).getTime()) / 86400000) : null;
          return { name: taskName(t), meta: [t.clients.name, 'Urgent delivery'].join(' · '), tag: 'Task', who: '',
                   late: n > 0, days: n > 0 ? n : 0, since: n === null ? 'No due date' : n > 0 ? daysWord(n) + ' late' : 'Due ' + dateWord(t.current_final_due_at),
                   tone: n > 0 ? '' : 'warn', url: '/admin/?s=work&open=' + encodeURIComponent(t.id), section: 'work' };
        });
      });
    } },
    { key: 'owed', title: function () { return 'Reports for ' + lastMonth().word; }, can: canReports, load: function () {
      var SM = window.ADspaceSmReport;
      return R.owed().then(function (items) {
        return items.filter(function (x) { return x.status !== 'published' && x.status !== 'review'; }).map(function (x) {
          var c = { slug: x.slug, id: x.client_id };
          return { name: (SM && SM.titleOf ? SM.titleOf({ kind: x.kind }) : x.kind) + ', ' + lastMonth().short,
                   meta: [x.brand || x.client, STAGE_WORD[x.status] || x.status].filter(Boolean).join(' · '), tag: 'Report',
                   who: x.assignee || '', late: Boolean(x.late), days: x.late ? reportLateDays(x) : 0,
                   since: x.late ? daysWord(reportLateDays(x)) + ' late' : 'Due ' + dateWord(x.due), tone: x.late ? '' : 'off',
                   url: x.report_id ? '/admin/?s=reports&report=' + encodeURIComponent(x.report_id)
                     : x.task_id && may('ops') ? '/admin/?s=work&open=' + encodeURIComponent(x.task_id)
                     : may('clients') ? clientUrl(c, 'engagements') : '/admin/?s=reports',
                   section: x.report_id ? 'reports' : x.task_id && may('ops') ? 'work' : may('clients') ? 'clients' : 'reports' };
        });
      });
    } },
    { key: 'confirm', title: 'Reports waiting for confirmation', can: canReports, load: function () {
      var SM = window.ADspaceSmReport;
      return R.inReview().then(function (list) {
        return list.map(function (r) {
          return { name: SM && SM.titleOf ? SM.titleOf(r) : r.title,
                   meta: [(r.clients && r.clients.name) || 'Client', 'In review'].join(' · '), tag: 'Report',
                   who: (r.clients && r.clients.owner) || '', days: daysSince(r.submitted_at), since: sinceWord(r.submitted_at), tone: 'warn',
                   url: '/admin/?s=reports&report=' + encodeURIComponent(r.id), section: 'reports' };
        });
      });
    } },
    { key: 'cold', title: 'Leads going cold', can: canLeads, load: function () {
      var STALE = window.ADspaceCRM.staleH();
      return R.clients().then(function (list) {
        var now = Date.now();
        return list.filter(function (c) { return c.stage === 'lead' || c.stage === 'proposal'; }).map(function (c) {
          return { c: c, h: (now - new Date(c.stage_since || c.created_at).getTime()) / 3600000 };
        }).filter(function (x) { return x.h > STALE[x.c.stage]; }).map(function (x) {
          var c = x.c, d = Math.floor(x.h / 24);
          return { name: c.name, meta: [(W.stage || {})[c.stage] || c.stage, 'Overdue'].join(' · '), tag: 'Lead', who: c.owner || '',
                   late: true, days: d, since: daysWord(d), url: clientUrl(c), section: 'clients' };
        });
      });
    } },
    { key: 'restricted', title: 'Restricted accounts', can: canClients, load: function () {
      return R.clients().then(function (list) {
        return list.filter(function (c) { return c.restricted_since; }).map(function (c) {
          return { name: c.name, meta: [RESTRICT_WORD[c.restricted_platform] || 'Account', 'Restricted', c.restricted_note].filter(Boolean).join(' · '),
                   tag: 'Client', who: c.owner || '', late: true, days: daysSince(c.restricted_since), since: sinceWord(c.restricted_since),
                   url: clientUrl(c), section: 'clients' };
        });
      });
    } },
    { key: 'requests', title: 'Unanswered requests', can: canRequests, load: function () {
      return R.requests().then(function (list) {
        return list.map(function (q) {
          var c = q.clients || {};
          return { name: [(W.rqKind || {})[q.kind] || q.kind, q.service_label].filter(Boolean).join(': '),
                   meta: [c.name || 'Client', (W.rqState || {})[q.state] || q.state].join(' · '), tag: 'Request', who: c.owner || '',
                   days: daysSince(q.created_at), since: sinceWord(q.created_at), tone: 'warn', url: clientUrl(c, 'services'), section: 'clients' };
        });
      });
    } },
    { key: 'sets', title: 'Sets waiting on the client', can: canSets, load: function () {
      return R.sets().then(function (list) {
        return list.map(function (x) {
          var c = x.s.clients || {};
          return { name: x.s.title, meta: [c.name || 'Client', x.ok + ' of ' + x.n + ' approved', x.ch ? x.ch + ' changes requested' : ''].filter(Boolean).join(' · '),
                   tag: 'Content Review', who: c.owner || '', days: daysSince(x.s.published_at || x.s.created_at),
                   since: sinceWord(x.s.published_at || x.s.created_at), tone: 'warn',
                   url: '/admin/?s=review&client=' + encodeURIComponent(c.id || x.s.client_id) + '&set=' + encodeURIComponent(x.s.id), section: 'review' };
        });
      });
    } },
    { key: 'noset', title: 'No set this month', can: canSets, load: function () {
      return R.noSet().then(function (list) {
        return list.map(function (x) {
          return { name: x.c.name, meta: 'No set this month' + (x.last ? ' · Last set ' + dateWord(x.last) : ''), tag: 'Content Review',
                   who: x.c.owner || '', days: 0, since: 'Not started', tone: 'off',
                   url: '/admin/?s=review&client=' + encodeURIComponent(x.c.id), section: 'review' };
        });
      });
    } },
    { key: 'bookings', title: 'Bookings past their date', can: canCamps, load: function () {
      var t0 = isoDay(today());
      return R.bookings().then(function (list) {
        return list.filter(function (o) { return o.state === 'pending_visit' || o.state === 'pending_draft' || o.state === 'changes'; }).map(function (o) {
          return { o: o, due: o.state === 'pending_visit' ? o.visit_date : o.submission_due };
        }).filter(function (x) { return x.due && String(x.due).slice(0, 10) < t0; }).map(function (x) {
          var o = x.o, cp = o.campaigns || {};
          return { name: (o.creators && o.creators.name) || 'Creator',
                   meta: [cp.title, o.state === 'pending_visit' ? 'Visit ' + dateWord(x.due) : 'Draft due ' + dateWord(x.due)].filter(Boolean).join(' · '),
                   tag: 'Campaign', who: cp.owner || '', late: true, days: daysSince(x.due), since: daysWord(daysSince(x.due)) + ' late',
                   url: '/admin/?s=campaigns&campaign=' + encodeURIComponent(o.campaign_id) + '&pane=schedule', section: 'campaigns' };
        });
      });
    } },
    { key: 'qc', title: 'Waiting for the quality check', can: canCamps, load: function () {
      return R.bookings().then(function (list) {
        return list.filter(function (o) { return o.state === 'submitted'; }).map(function (o) {
          var cp = o.campaigns || {};
          return { name: (o.creators && o.creators.name) || 'Creator', meta: [cp.title, (W.step || {}).submitted || 'Submitted'].filter(Boolean).join(' · '),
                   tag: 'Campaign', who: cp.owner || '', days: daysSince(o.submitted_at), since: sinceWord(o.submitted_at), tone: 'warn',
                   url: '/admin/?s=campaigns&campaign=' + encodeURIComponent(o.campaign_id) + '&pane=creators', section: 'campaigns' };
        });
      });
    } },
    { key: 'unsigned', title: 'Letters of Offer not yet signed', can: function () { return may('clients.documents', 'manage'); }, load: function () {
      return R.letters().then(function (list) {
        return list.map(function (d) {
          var c = d.clients || {};
          return { name: d.number, meta: [c.name || 'Client', 'Issued ' + dateWord(d.issued_at)].join(' · '), tag: 'Document', who: c.owner || '',
                   days: daysSince(d.issued_at), since: daysWord(daysSince(d.issued_at)), tone: 'warn', url: clientUrl(c, 'documents'), section: 'clients' };
        });
      });
    } },
    { key: 'reviews', title: function () { return 'Reviews for ' + lastMonth().word; }, can: function () { return may('team.performance'); }, load: function () {
      var P = window.ADspacePerf, words = (P && P.status) || {};
      return R.reviews().then(function (list) {
        return list.filter(function (r) { return r.status !== 'final'; }).map(function (r) {
          var w = words[r.status] || [r.status === 'none' ? 'Not started' : r.status, ''];
          return { name: 'Review, ' + lastMonth().short, meta: w[0], tag: 'Review', who: r.name, days: 0,
                   since: w[0], tone: r.status === 'none' ? 'off' : 'warn',
                   url: '/admin/?s=team&tab=performance&m=' + lastMonth().key, section: 'team' };
        });
      });
    } }
  ];
  function rank(r) { return r.late ? 0 : r.tone === 'off' ? 2 : 1; }
  function attention() {
    var live = SOURCES.filter(function (s) { return s.can(); });
    return Promise.all(live.map(function (s) {
      return s.load().then(function (rs) { return { rows: rs }; }, function (e) {
        return { failed: typeof s.title === 'function' ? s.title() : s.title, why: (e && e.message) || 'The read failed.' };
      });
    })).then(function (all) {
      var out = [], failed = [];
      all.forEach(function (a) { if (a.failed) failed.push(a); else out = out.concat(a.rows); });
      out.sort(function (a, b) { return rank(a) - rank(b) || b.days - a.days || String(a.name).localeCompare(String(b.name)); });
      return { rows: out, failed: failed };
    });
  }

  /* ---- Today at a glance --------------------------------------------------------
     A signal a line: its words, its count, its state. Each asks its source's
     permission and reads through the shared reads. */
  var SIGNALS = [
    { key: 'late', title: 'Late tasks', can: canFigures, load: function () {
      return R.report().then(function (d) { var n = (d.late || []).length; return { n: n, word: n ? 'Late' : 'None', tone: n ? 'danger' : 'off' }; });
    } },
    { key: 'owed', title: function () { return 'Reports owed for ' + LONG[lastMonth().start.getMonth()]; }, can: canReports, load: function () {
      return R.owed().then(function (items) {
        var open = items.filter(function (x) { return x.status !== 'published' && x.status !== 'review'; });
        var late = open.filter(function (x) { return x.late; }).length;
        return { n: open.length, word: late ? late + ' late' : open.length ? 'Waiting' : 'None', tone: late ? 'danger' : open.length ? 'warn' : 'off' };
      });
    } },
    { key: 'cold', title: 'Leads going cold', can: canLeads, load: function () {
      return SOURCES.filter(function (s) { return s.key === 'cold'; })[0].load().then(function (l) {
        return { n: l.length, word: l.length ? 'Overdue' : 'None', tone: l.length ? 'danger' : 'off' };
      });
    } },
    { key: 'sets', title: 'Sets waiting on clients', can: canSets, load: function () {
      return R.sets().then(function (l) { return { n: l.length, word: l.length ? 'Waiting' : 'None', tone: l.length ? 'warn' : 'off' }; });
    } },
    { key: 'requests', title: 'Unanswered client requests', can: canRequests, load: function () {
      return R.requests().then(function (l) { return { n: l.length, word: l.length ? 'Waiting' : 'None', tone: l.length ? 'warn' : 'off' }; });
    } },
    { key: 'active', title: 'Active clients', can: canClients, load: function () {
      return R.clients().then(function (l) {
        var n = l.filter(function (c) { return c.stage === 'active'; }).length;
        return { n: n, word: n ? 'Active' : 'None', tone: n ? 'ok' : 'off' };
      });
    } }
  ];
  function titleOf(x) { return typeof x.title === 'function' ? x.title() : x.title; }

  /* ---- The tiles -------------------------------------------------------------------
     A tile: its label, its figure, one line under it and, where the figure
     has a history, its trend. `load()` answers `{ fig, sub, tone, spark,
     bar }`. */
  var SALES = [
    { key: 'leads', title: 'New leads', can: canLeads, load: function () {
      return Promise.all([figuresFor(rangeOf(period)), figuresFor(prevOf(period)), figuresFor(sixMonths())]).then(function (f) {
        return { fig: String(f[0].newLeads.length), sub: delta(f[0].newLeads.length, f[1].newLeads.length),
                 spark: f[2].months.map(function (m) { return m.newLeads; }) };
      });
    } },
    { key: 'won', title: 'Won', can: canLeads, load: function () {
      return Promise.all([figuresFor(rangeOf(period)), figuresFor(prevOf(period)), figuresFor(sixMonths())]).then(function (f) {
        return { fig: String(f[0].won.length), sub: delta(f[0].won.length, f[1].won.length),
                 spark: f[2].months.map(function (m) { return m.won; }) };
      });
    } },
    { key: 'churned', title: 'Churned', can: canLeads, load: function () {
      return Promise.all([figuresFor(rangeOf(period)), figuresFor(prevOf(period)), figuresFor(sixMonths())]).then(function (f) {
        return { fig: String(f[0].churned.length), sub: delta(f[0].churned.length, f[1].churned.length),
                 spark: f[2].months.map(function (m) { return m.churned; }) };
      });
    } },
    /* Committed monthly value for whoever may open a client's Services, from
       the lines that part opens; Active clients for everyone else. */
    { key: 'value', title: function () { return canValue() ? 'Committed monthly value' : 'Active clients'; }, can: canClients, load: function () {
      if (canValue()) {
        return R.lines().then(function (lines) { return figuresFor(rangeOf(period), lines); }).then(function (f) {
          var won = f.money && f.money.won, any = won && Object.keys(won).some(function (k) { return won[k]; });
          return { fig: moneyWord(f.money && f.money.active), money: true,
                   sub: any ? moneyWord(won) + ' won ' + periodName(period) : 'None won ' + periodName(period) };
        });
      }
      return Promise.all([figuresFor(rangeOf(period)), figuresFor(sixMonths())]).then(function (f) {
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
    { key: 'late', title: 'Late', can: canFigures, load: function () {
      return R.report().then(function (d) {
        var l = d.late || [], top = l.reduce(function (a, t) { return Math.max(a, Number(t.days_over) || 0); }, 0);
        return { fig: String(l.length), tone: l.length ? 'err' : '', sub: l.length ? 'Oldest ' + daysWord(top) + ' late' : 'None late' };
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
      { key: 'ontime', title: 'On-time delivery by month', can: canFigures, all: ['My Work', '/admin/?s=work', 'work'], load: function () {
        return R.months().then(function (all) {
          var cats = all.map(function (x) {
            var f = x.d.on_time || {}, n = Number(f.reached || 0);
            return { label: x.m.label, long: x.m.long, values: [n ? Math.round(Number(f.met || 0) / n * 100) : null], n: n, met: Number(f.met || 0) };
          });
          if (!cats.some(function (c) { return c.values[0] != null; })) return { empty: 'No tasks reached client review in the last six months.' };
          return { kind: 'line', max: 100, none: 'None reached client review', cats: cats, series: [{ label: 'On time' }],
            fmt: function (v) { return Math.round(Number(v) || 0) + '%'; },
            table: { heads: ['Month', 'Reached client review', 'On time', 'Rate'], rows: cats.map(function (c) {
              return [c.long, String(c.n), String(c.met), c.values[0] == null ? '—' : c.values[0] + '%'];
            }) } };
        });
      } },
      { key: 'active', title: 'Active clients by month', can: canClients,
        all: function () { return ['Clients', '/admin/?s=clients', 'clients']; }, load: function () {
        return figuresFor(sixMonths()).then(function (f) {
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
        return figuresFor(rangeOf(period)).then(function (f) {
          var words = ['New leads', 'Contacted', 'Proposal sent', 'Became clients'];
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
        return figuresFor(rangeOf(period)).then(function (f) {
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
        return (val ? R.lines() : Promise.resolve(null)).then(function (lines) { return figuresFor(rangeOf(period), lines); }).then(function (f) {
          var pct = function (a, b) { return b ? Math.round(a / b * 100) + '%' : '—'; };
          var decided = f.won.length + f.lost.length;
          var rowsOf = [
            ['Lost leads', String(f.lost.length), 'Past before ever Active'],
            ['Paused', String(f.paused.length), f.pausedNow.length + ' paused now'],
            ['Resumed', String(f.resumed.length), 'Paused back to Active'],
            ['Win-backs', String(f.winback.length), 'Past back to Active'],
            ['Lead to won', f.medianToWin === null ? '—' : daysWord(f.medianToWin), 'Median'],
            ['Conversion', pct(f.won.length, decided), 'Won of the leads decided'],
            ['Churn rate', pct(f.churned.length, f.activeStart), 'Churned of those active at the start']
          ];
          if (val && f.money) {
            rowsOf.push(['Monthly value won', moneyWord(f.money.won), 'A month of the lines won']);
            rowsOf.push(['Monthly value lost', moneyWord(f.money.churned), 'A month of the lines churned']);
          }
          return { html: '<dl class="ovw-facts">' + rowsOf.map(function (r) {
            return '<div><dt>' + esc(r[0]) + '<small>' + esc(r[2]) + '</small></dt><dd>' + esc(r[1]) + '</dd></div>';
          }).join('') + '</dl>' };
        });
      } },
      /* Who brought the leads in and who kept the clients (from Clients ·
         Sales, 2026-10-12): counts only, never a ranking. */
      { key: 'owners', title: 'By person in charge', can: canLeads,
        all: ['Clients', '/admin/?s=clients', 'clients'], load: function () {
        return figuresFor(rangeOf(period)).then(function (f) {
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
        return figuresFor(rangeOf(period)).then(function (f) {
          var rowsOf = Object.keys(f.bySource).map(function (k) { return { label: k, value: f.bySource[k].length }; })
            .sort(function (a, b) { return b.value - a.value || a.label.localeCompare(b.label); });
          if (!rowsOf.length) return { empty: 'No new leads ' + periodName(period) + '.' };
          return { kind: 'bars', inline: true, rows: rowsOf, valueHead: 'New leads' };
        });
      } },
      { key: 'reasons', title: 'Why clients paused or left', can: canClients,
        all: function () { return ['Clients', '/admin/?s=clients', 'clients']; },
        load: function () {
        return figuresFor(rangeOf(period)).then(function (f) {
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
          var list = d.open_by_person.filter(function (r) { return Number(r.open) > 0; });
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
      { key: 'reports', title: function () { return 'Reports for ' + LONG[lastMonth().start.getMonth()]; }, can: canReports, all: ['Reports', '/admin/?s=reports', 'reports'], load: function () {
        return R.owed().then(function (items) {
          if (!items.length) return { empty: 'No reports owed.' };
          var n = function (st) { return items.filter(function (x) { return x.status === st; }).length; };
          var lateNone = items.some(function (x) { return x.status === 'none' && x.late; });
          return { kind: 'pie', total: true, rows: [{ label: 'Published', value: n('published'), tone: 'ok' }, { label: 'In review', value: n('review'), tone: 'warn' },
            { label: 'Confirmed', value: n('confirmed'), tone: 'warn' }, { label: 'Draft', value: n('draft'), tone: 'off' },
            { label: 'Not started', value: n('none'), tone: lateNone ? 'err' : 'off' }] };
        });
      } },
      { key: 'bookings', title: 'Creator bookings', can: canCamps, all: ['Campaigns', '/admin/?s=campaigns', 'campaigns'], load: function () {
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
  var ALL = [].concat(SOURCES, SIGNALS, SALES, OPS, [].concat.apply([], CHARTS));
  function any() { return ALL.some(function (c) { return c.can(); }); }

  // ---- Drawing ----------------------------------------------------------------------
  function fail(body, title, e, again) {
    UI.failLine(body, title || 'This card', (e && e.message) || 'The read failed.', again);
  }
  function glance(box) {
    var meter = canFigures(), sigs = SIGNALS.filter(function (s) { return s.can(); });
    if (!meter && !sigs.length) return;
    var card = document.createElement('section');
    card.className = 'chartcard ovw-glance' + (meter ? '' : ' is-plain');
    card.id = 'ovwGlance';
    card.innerHTML = (meter ? '<div class="ovw-meter" id="ovwMeter"></div>' : '') +
      (sigs.length ? '<div class="ovw-sigs"><div class="ovw-cardhead"><h3>Needs attention today</h3>' +
        '<button class="btn btn-quiet btn-sm ovgo" type="button" data-a="list"><span class="ovgo-word">Open list</span>' + CHEV + '</button></div>' +
        '<div class="ovw-sig-rows"></div></div>' : '');
    box.appendChild(card);
    if (meter) {
      var mbox = card.querySelector('#ovwMeter');
      var runM = function () {
        UI.skeleton(mbox, 2);
        R.report().then(function (d) {
          var f = d.on_time || {}, n = Number(f.reached || 0), met = Number(f.met || 0);
          mbox.innerHTML = '';
          /* The ring stands whatever the period holds (the user, 2026-10-12):
             with nothing reached client review it is empty and reads a dash. */
          CH.draw(mbox, { kind: 'meter', name: 'On-time delivery', word: 'On-time delivery', valueHead: 'Tasks',
            rows: [{ label: 'On time', value: met, tone: 'ok' }, { label: 'Late', value: n - met }] });
        }).catch(function (e) { fail(mbox, 'On-time delivery', e, runM); });
      };
      runM();
    }
    var list = card.querySelector('[data-a="list"]');
    if (list) list.addEventListener('click', function () {
      var a = $('ovwAttention');
      if (a) { a.scrollIntoView({ block: 'start', behavior: 'smooth' }); var first = a.querySelector('.ovw-att-row'); if (first) first.focus({ preventScroll: true }); }
    });
    var host = card.querySelector('.ovw-sig-rows');
    sigs.forEach(function (s) {
      var row = document.createElement('div');
      row.className = 'ovw-sig';
      row.setAttribute('data-sig', s.key);
      row.innerHTML = '<span class="ovw-sig-name"></span><b class="ovw-sig-n"><span class="skel skel-w"></span></b><span class="ovw-sig-word"></span>';
      row.firstChild.textContent = titleOf(s);
      host.appendChild(row);
      s.load().then(function (o) {
        row.querySelector('.ovw-sig-n').textContent = String(o.n);
        row.querySelector('.ovw-sig-word').innerHTML = '<span class="chip-state tone is-' + o.tone + '">' + esc(o.word) + '</span>';
      }).catch(function () {
        row.querySelector('.ovw-sig-n').textContent = '—';
        row.querySelector('.ovw-sig-word').innerHTML = '<span class="ovw-sig-fail">Could not load.</span>';
      });
    });
  }
  function tile(grid, t) {
    var el = document.createElement('article');
    el.className = 'chartcard ovw-kpi';
    el.setAttribute('data-tile', t.key);
    el.innerHTML = '<span class="ovw-kpi-label"></span><b class="ovw-kpi-fig"><span class="skel skel-w"></span></b>' +
      '<span class="ovw-kpi-sub"></span><span class="ovw-kpi-trend"></span>';
    el.querySelector('.ovw-kpi-label').textContent = titleOf(t);
    grid.appendChild(el);
    var run = function () {
      t.load().then(function (o) {
        var fig = el.querySelector('.ovw-kpi-fig');
        fig.textContent = o.fig;
        fig.className = 'ovw-kpi-fig' + (o.tone ? ' is-' + o.tone : '') + (o.money ? ' is-money' : '');
        el.querySelector('.ovw-kpi-label').textContent = titleOf(t);
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
  function turn(to) {
    if (to === page) return;
    page = to;
    build(false);
    window.scrollTo(0, 0);
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
    b.innerHTML = page === 'summary' ? '<span>Continue to Detail</span>' + CHEV : '<span>Back to Summary</span>';
    b.addEventListener('click', function () { turn(page === 'summary' ? 'detail' : 'summary'); });
    row.appendChild(b);
    box.appendChild(row);
  }

  var SHOWN = 5;
  function list(box) {
    if (!SOURCES.some(function (s) { return s.can(); })) return;
    var card = document.createElement('section');
    card.className = 'chartcard ovw-card ovw-att';
    card.id = 'ovwAttention';
    card.innerHTML = '<div class="ovw-cardhead"><h3>Needs attention</h3><span class="ovw-count" hidden></span></div><div class="ovw-body"></div>';
    box.appendChild(card);
    var body = card.querySelector('.ovw-body');
    var run = function () {
      UI.skeleton(body, 4);
      attention().then(function (a) {
        var count = card.querySelector('.ovw-count');
        var late = a.rows.some(function (r) { return r.late; });
        count.hidden = !a.rows.length;
        count.textContent = String(a.rows.length);
        count.className = 'ovw-count tone' + (late ? ' is-danger' : '');
        body.innerHTML = '';
        a.failed.forEach(function (f) {
          var host = document.createElement('div');
          body.appendChild(host);
          UI.failLine(host, f.failed, f.why, run);
        });
        if (!a.rows.length) {
          if (!a.failed.length) UI.emptyLine(body, 'Nothing waiting.');
          return;
        }
        var head = '<div class="ovw-att-head" aria-hidden="true"><span>What</span><span>Section</span><span>Who</span><span>Since</span></div>';
        var html = a.rows.map(function (r, i) {
          var since = r.late ? '<b class="is-err">' + esc(r.since) + '</b>'
            : '<span class="chip-state tone is-' + (r.tone || 'warn') + '">' + esc(r.since) + '</span>';
          return '<button class="ovw-att-row" type="button" data-i="' + i + '"' + (i >= SHOWN ? ' hidden' : '') + '>' +
            '<span class="ovw-att-what"><b>' + esc(r.name) + '</b>' + (r.meta ? '<small>' + esc(r.meta) + '</small>' : '') + '</span>' +
            '<span class="ovw-att-sec"><span class="chip">' + esc(r.tag) + '</span></span>' +
            '<span class="ovw-att-who">' + (r.who ? esc(r.who) : '<span class="ovw-dash" aria-label="No one">—</span>') + '</span>' +
            '<span class="ovw-att-since">' + since + '</span></button>';
        }).join('');
        var more = a.rows.length - SHOWN;
        var holder = document.createElement('div');
        holder.className = 'ovw-att-rows';
        holder.innerHTML = head + html;
        body.appendChild(holder);
        /* Five rows, then the rest a press away; pressed again, the list
           folds back to five (the user, 2026-10-12: "so it is not
           inadvertently long"; "5 show only"). */
        var DOWN = '<svg class="ovw-more-chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 9l6 6 6-6"/></svg>';
        if (more > 0) body.insertAdjacentHTML('beforeend', '<button class="btn btn-sm ovw-more" type="button" aria-expanded="false" aria-controls="ovwAttention">' +
          '<span>Show ' + more + ' more</span>' + DOWN + '</button>');
        Array.prototype.forEach.call(holder.querySelectorAll('.ovw-att-row'), function (b) {
          var r = a.rows[Number(b.getAttribute('data-i'))];
          b.addEventListener('click', function () { go(r.url, r.section); });
        });
        var mb = body.querySelector('.ovw-more');
        if (mb) mb.addEventListener('click', function () {
          var open = mb.getAttribute('aria-expanded') !== 'true';
          var rows = Array.prototype.slice.call(holder.querySelectorAll('.ovw-att-row')).slice(SHOWN);
          rows.forEach(function (b) { b.hidden = !open; });
          mb.setAttribute('aria-expanded', String(open));
          mb.firstChild.textContent = open ? 'Show fewer' : 'Show ' + more + ' more';
          if (open && rows[0]) rows[0].focus();
          if (!open) { card.scrollIntoView({ block: 'nearest' }); mb.focus({ preventScroll: true }); }
        });
      }).catch(function (e) { fail(body, 'Needs attention', e, run); });
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
    var now = new Date(), h = now.getHours(), m = String(now.getMinutes()).padStart(2, '0');
    head.querySelector('#ovwSpan').textContent = spanWord(rangeOf(period)) + ' · As at ' + ((h % 12) || 12) + ':' + m + (h < 12 ? ' am' : ' pm');
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
      tiles(box);
      charts(box, PAGE1);
      list(box);
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
