/*
 * Overview — the start page for a group that manages a section.
 *
 * One page that answers, section by section, what is waiting: late work and
 * who carries the open work, leads going cold, requests nobody has answered,
 * content sets the client has not decided, bookings past their date, letters
 * out unsigned, reports waiting for confirmation, and the month's reviews not
 * yet final. Each card asks its own permission before it reads anything, so a
 * card the person cannot read is not drawn and a section with no cards takes
 * its heading with it, as the rail's groups do. Every read goes through the
 * section's own tables under row level security or its own function; nothing
 * here is money (the user, 2026-09-28).
 *
 * The page reads again each time it is opened and never polls. A row opens
 * the record; View all opens the section.
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
  /* A section's cards are for whoever holds Full Access (manage) on it or
     its part (the user, 2026-10-03: Clients showed to a group at Manage);
     the granted parts (ops.reports, ops.all, team.performance) are their own
     grant and are asked at it. */
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
  function daysWord(n) { return n === 1 ? '1 day' : n + ' days'; }
  function sinceWord(v) { var n = daysSince(v); return n ? daysWord(n) : 'Today'; }
  function dateWord(v) {
    var d = new Date(String(v).length === 10 ? v + 'T00:00:00' : v);
    return isNaN(d.getTime()) ? '' : d.getDate() + ' ' + MON[d.getMonth()] + ' ' + d.getFullYear();
  }
  // Last month: its first day, its last day, its name and its address key.
  function lastMonth() {
    var now = new Date();
    var a = new Date(now.getFullYear(), now.getMonth() - 1, 1), z = new Date(now.getFullYear(), now.getMonth(), 0);
    return { start: a, end: z, word: LONG[a.getMonth()] + ' ' + a.getFullYear(),
             key: a.getFullYear() + '-' + String(a.getMonth() + 1).padStart(2, '0') };
  }
  function isoDay(d) {
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  }
  var CHEV = '<svg class="ovgo-chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
    'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 18l6-6-6-6"/></svg>';

  /* A read that answers `{ error }` from a function after the page's own
     check passed is a refusal, and a refusal is never drawn as an empty card. */
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

  // ---- One report read shared by the My Work cards ---------------------------
  var reportP = null;
  function report() {
    if (!reportP) {
      reportP = db.rpc('ops_report', {}).then(rows);
      reportP.catch(function () { reportP = null; });
    }
    return reportP;
  }

  /* ---- The cards -------------------------------------------------------------
     A list card: `load()` answers `{ rows: [{ name, meta, fig, figTone, age,
     url, section }], count, warn }`. A chart card: `load()` answers a spec for
     ADspaceChart.draw, or `{ empty }`. Sections run in the rail's order. */
  /* How long a stage may run, from the Clients list's own rule. */
  function staleH() { return (window.ADspaceCRM && window.ADspaceCRM.staleH) || { lead: 48, proposal: 21 * 24 }; }
  var LETTERS = ['offer', 'intent', 'cover'];

  var SECTIONS = [
    { head: 'My Work', key: 'work', cards: [
      { key: 'late', title: 'Late tasks', can: function () { return may('ops.reports'); },
        all: ['/admin/?s=work&view=report', 'work'], warn: true, empty: 'No late tasks.',
        load: function () {
          return report().then(function (d) {
            var list = (d.late || []).slice().sort(function (a, b) { return (b.days_over || 0) - (a.days_over || 0); });
            return { count: list.length, rows: list.map(function (t) {
              return { name: t.title || ('#WT' + String(t.task_no || '').padStart(5, '0')),
                       meta: [t.owner || 'No task owner', t.client].filter(Boolean).join(' · '),
                       fig: daysWord(Number(t.days_over) || 0) + ' over', figTone: 'warn', age: t.stage || '',
                       url: '/admin/?s=work&open=' + encodeURIComponent(t.task_id), section: 'work' };
            }) };
          });
        } },
      { key: 'load', title: 'Open work by person', chart: true, can: function () { return may('ops.all') && may('ops.reports'); },
        load: function () {
          return report().then(function (d) {
            if (!Array.isArray(d.open_by_person)) throw new Error('This needs a database update.');
            var list = d.open_by_person.filter(function (r) { return Number(r.open) > 0; });
            if (!list.length) return { empty: 'No open tasks.' };
            return { kind: 'bars', title: 'Open work by person',
              rows: list.map(function (r) {
                var late = Number(r.late) || 0;
                return { label: r.name, value: Number(r.open) || 0,
                         note: late ? late + ' late' : '', noteTone: late ? 'warn' : '' };
              }),
              fmt: function (v) { return v + (Number(v) === 1 ? ' open task' : ' open tasks'); },
              table: { heads: ['Task Owner', 'Open', 'Late'],
                       rows: list.map(function (r) { return [r.name, String(r.open), String(r.late || 0)]; }) } };
          });
        } },
      { key: 'ontime', title: 'On-time delivery', chart: true, can: function () { return may('ops.reports'); },
        load: function () {
          var ms = CH.months(6);
          return Promise.all(ms.map(function (m) {
            return db.rpc('ops_report', { p_from: m.start.toISOString(), p_to: m.end.toISOString() })
              .then(rows).then(function (d) { return d.on_time || {}; });
          })).then(function (all) {
            var cats = ms.map(function (m, i) {
              var f = all[i] || {}, n = Number(f.reached || 0);
              return { label: m.label, long: m.long, values: [n ? Math.round(Number(f.met || 0) / n * 100) : null],
                       n: n, met: Number(f.met || 0) };
            });
            if (!cats.some(function (c) { return c.values[0] != null; })) {
              return { empty: 'No tasks reached client review in the last six months.' };
            }
            return { kind: 'line', title: 'On-time delivery', max: 100, none: 'None reached client review',
              cats: cats, series: [{ label: 'On time' }],
              fmt: function (v) { return Math.round(Number(v) || 0) + '%'; },
              table: { heads: ['Month', 'Reached client review', 'On time', 'Rate'],
                       rows: cats.map(function (c) {
                         return [c.long, String(c.n), String(c.met), c.values[0] == null ? '—' : c.values[0] + '%'];
                       }) } };
          });
        } }
    ] },

    { head: 'Clients', key: 'clients', cards: [
      { key: 'cold', title: 'Leads going cold', can: function () { return may('clients', 'manage'); },
        all: ['/admin/?s=clients', 'clients'], warn: true, empty: 'No leads over their time.',
        load: function () {
          return db.from('clients').select('id, name, slug, stage, stage_since, owner, created_at')
            .in('stage', ['lead', 'proposal']).then(rows).then(function (list) {
              var now = Date.now(), STALE_H = staleH();
              var over = (list || []).map(function (c) {
                var since = new Date(c.stage_since || c.created_at).getTime();
                return { c: c, h: (now - since) / 3600000 };
              }).filter(function (x) { return x.h > STALE_H[x.c.stage]; })
                .sort(function (a, b) { return b.h - a.h; });
              return { count: over.length, rows: over.map(function (x) {
                var c = x.c;
                return { name: c.name, meta: [(W.stage || {})[c.stage] || c.stage, c.owner].filter(Boolean).join(' · '),
                         fig: daysWord(Math.floor(x.h / 24)), figTone: 'warn', age: 'Overdue',
                         url: clientUrl(c), section: 'clients' };
              }) };
            });
        } },
      { key: 'intake', title: 'New leads and new clients', chart: true, can: function () { return may('clients', 'manage'); },
        load: function () {
          return db.from('clients').select('id, created_at, stage_log').then(rows).then(function (list) {
            var ms = CH.months(6), at = {};
            ms.forEach(function (m, i) { at[m.key] = i; });
            var leads = ms.map(function () { return 0; }), active = ms.map(function () { return 0; });
            (list || []).forEach(function (c) {
              var k = CH.monthKey(c.created_at);
              if (k in at) leads[at[k]]++;
              (Array.isArray(c.stage_log) ? c.stage_log : []).forEach(function (e) {
                if (!e || e.stage !== 'active') return;
                var ka = CH.monthKey(e.at);
                if (ka in at) active[at[ka]]++;
              });
            });
            if (!leads.some(Boolean) && !active.some(Boolean)) return { empty: 'No new leads in the last six months.' };
            return { kind: 'columns', title: 'New leads and new clients',
              cats: ms.map(function (m, i) { return { label: m.label, long: m.long, values: [leads[i], active[i]] }; }),
              series: [{ label: 'New leads' }, { label: 'Became active', tone: 'ok' }],
              fmt: function (v) { return String(v); } };
          });
        } },
      { key: 'requests', title: 'Unanswered requests', can: function () { return may('clients.requests', 'manage'); },
        all: ['/admin/?s=clients', 'clients'], empty: 'No requests waiting.',
        load: function () {
          return db.from('client_requests').select('id, kind, service_label, state, created_at, client_id, clients(id, name, slug)')
            .in('state', ['requested', 'reviewing']).is('withdrawn_at', null).order('created_at', { ascending: true })
            .then(rows).then(function (list) {
              list = list || [];
              return { count: list.length, rows: list.map(function (q) {
                var c = q.clients || {};
                return { name: c.name || 'Client', meta: [(W.rqKind || {})[q.kind] || q.kind, q.service_label].filter(Boolean).join(' · '),
                         fig: (W.rqState || {})[q.state] || q.state, age: sinceWord(q.created_at),
                         url: clientUrl(c, 'services'), section: 'clients' };
              }) };
            });
        } }
    ] },

    { head: 'Content Review', key: 'review', cards: [
      { key: 'sets', title: 'Sets waiting on the client', can: function () { return may('review.sets', 'manage'); },
        all: ['/admin/?s=review', 'review'], empty: 'No sets waiting.',
        load: function () {
          return db.from('batches').select('id, title, client_id, published_at, created_at, clients(id, name, slug)')
            .eq('published', true).order('created_at', { ascending: false }).limit(200).then(rows).then(function (sets) {
              sets = sets || [];
              if (!sets.length) return { count: 0, rows: [] };
              var ids = sets.map(function (s) { return s.id; });
              return db.from('posts').select('*').in('batch_id', ids).then(rows).then(function (posts) {
                posts = posts || [];
                var pids = posts.map(function (p) { return p.id; });
                var reviews = pids.length
                  ? db.from('reviews').select('*').in('post_id', pids)
                      .order('created_at', { ascending: false }).then(rows)
                  : Promise.resolve([]);
                return reviews.then(function (revs) {
                  var latest = {};
                  var reset = {}, round = {};
                  posts.forEach(function (p) { reset[p.id] = p.review_reset_at; round[p.id] = p.round || 1; });
                  (revs || []).forEach(function (r) {
                    /* A team approval taken back no longer stands. */
                    if (latest[r.post_id] || r.undone_at) return;
                    /* Only a decision on the round on show counts: a revised
                       post waits on the client again (2026-09-30). */
                    if ((r.round || 1) !== round[r.post_id]) return;
                    if (reset[r.post_id] && new Date(r.created_at) < new Date(reset[r.post_id])) return;
                    latest[r.post_id] = r;
                  });
                  var out = sets.map(function (s) {
                    var mine = posts.filter(function (p) { return p.batch_id === s.id; });
                    var ok = 0, ch = 0;
                    mine.forEach(function (p) {
                      var d = latest[p.id];
                      if (d && d.decision === 'approved') ok++; else if (d) ch++;
                    });
                    return { s: s, n: mine.length, ok: ok, ch: ch };
                  }).filter(function (x) { return x.n && x.ok < x.n; })
                    .sort(function (a, b) { return new Date(a.s.published_at || a.s.created_at) - new Date(b.s.published_at || b.s.created_at); });
                  return { count: out.length, rows: out.map(function (x) {
                    var c = x.s.clients || {};
                    return { name: c.name || 'Client',
                             meta: x.s.title + (x.ch ? ' · ' + x.ch + ' changes requested' : ''),
                             fig: x.ok + ' of ' + x.n + ' approved', age: sinceWord(x.s.published_at || x.s.created_at),
                             url: '/admin/?s=review&client=' + encodeURIComponent(c.id || x.s.client_id) + '&set=' + encodeURIComponent(x.s.id),
                             section: 'review' };
                  }) };
                });
              });
            });
        } },
      { key: 'noset', title: 'No set this month', can: function () { return may('review.sets', 'manage'); },
        all: ['/admin/?s=review', 'review'], empty: 'Every active client has a set this month.',
        load: function () {
          var first = new Date(); first = new Date(first.getFullYear(), first.getMonth(), 1);
          return Promise.all([
            db.from('clients').select('id, name, slug').eq('stage', 'active').eq('review_hidden', false).order('name').then(rows),
            db.from('batches').select('client_id, created_at').order('created_at', { ascending: false }).then(rows)
          ]).then(function (r) {
            var last = {};
            (r[1] || []).forEach(function (b) { if (!last[b.client_id]) last[b.client_id] = b.created_at; });
            var none = (r[0] || []).filter(function (c) { return !last[c.id] || new Date(last[c.id]) < first; });
            return { count: none.length, rows: none.map(function (c) {
              return { name: c.name, meta: last[c.id] ? 'Last set ' + dateWord(last[c.id]) : 'No sets',
                       fig: '', age: '', url: '/admin/?s=review&client=' + encodeURIComponent(c.id), section: 'review' };
            }) };
          });
        } }
    ] },

    { head: 'Creator Campaigns', key: 'campaigns', cards: [
      { key: 'bookings', title: 'Bookings past their date', can: function () { return may('campaigns.campaigns', 'manage'); },
        all: ['/admin/?s=campaigns', 'campaigns'], warn: true, empty: 'No bookings past their date.',
        load: function () {
          var t0 = isoDay(today());
          return db.from('campaign_options')
            .select('id, state, visit_date, submission_due, campaign_id, campaigns(id, title), creators(name)')
            .in('state', ['pending_visit', 'pending_draft', 'changes']).then(rows).then(function (list) {
              var late = (list || []).map(function (o) {
                var due = o.state === 'pending_visit' ? o.visit_date : o.submission_due;
                return { o: o, due: due };
              }).filter(function (x) { return x.due && String(x.due).slice(0, 10) < t0; })
                .sort(function (a, b) { return String(a.due) < String(b.due) ? -1 : 1; });
              return { count: late.length, rows: late.map(function (x) {
                var o = x.o, cp = o.campaigns || {};
                return { name: (o.creators && o.creators.name) || 'Creator',
                         meta: [cp.title, (W.step || {})[o.state] || o.state].filter(Boolean).join(' · '),
                         fig: daysWord(daysSince(x.due)) + ' over', figTone: 'warn',
                         age: o.state === 'pending_visit' ? 'Visit ' + dateWord(x.due) : 'Draft due ' + dateWord(x.due),
                         url: '/admin/?s=campaigns&campaign=' + encodeURIComponent(o.campaign_id) + '&pane=schedule',
                         section: 'campaigns' };
              }) };
            });
        } },
      { key: 'qc', title: 'Waiting for the quality check', can: function () { return may('campaigns.campaigns', 'manage'); },
        all: ['/admin/?s=campaigns', 'campaigns'], empty: 'No drafts waiting.',
        load: function () {
          return db.from('campaign_options')
            .select('id, submitted_at, campaign_id, campaigns(id, title), creators(name)')
            .eq('state', 'submitted').order('submitted_at', { ascending: true }).then(rows).then(function (list) {
              list = list || [];
              return { count: list.length, rows: list.map(function (o) {
                var cp = o.campaigns || {};
                return { name: (o.creators && o.creators.name) || 'Creator', meta: cp.title || '',
                         fig: (W.step || {}).submitted || 'Submitted', age: sinceWord(o.submitted_at),
                         url: '/admin/?s=campaigns&campaign=' + encodeURIComponent(o.campaign_id) + '&pane=creators',
                         section: 'campaigns' };
              }) };
            });
        } }
    ] },

    { head: 'Documents', key: 'register', cards: [
      { key: 'unsigned', title: 'Letters of Offer not yet signed', can: function () { return may('clients.documents', 'manage'); },
        all: ['/admin/?s=register', 'register'], empty: 'No letters waiting.',
        load: function () {
          return db.from('client_documents')
            .select('id, number, issued_at, client_id, clients(id, name, slug)')
            .in('kind', LETTERS).is('signed_at', null).is('voided_at', null).is('superseded_by', null)
            .order('issued_at', { ascending: true }).then(rows).then(function (list) {
              list = list || [];
              return { count: list.length, rows: list.map(function (d) {
                var c = d.clients || {};
                return { name: c.name || 'Client', meta: d.number, fig: daysWord(daysSince(d.issued_at)) + ' out',
                         age: 'Issued ' + dateWord(d.issued_at), url: clientUrl(c, 'documents'), section: 'clients' };
              }) };
            });
        } }
    ] },

    { head: 'Reports', key: 'reports', cards: [
      { key: 'confirm', title: 'Waiting for confirmation', can: function () { return may('reports', 'manage'); },
        all: ['/admin/?s=reports', 'reports'], empty: 'No reports waiting.',
        load: function () {
          var SM = window.ADspaceSmReport;
          return db.from('sm_reports').select('id, kind, title, period_start, period_end, submitted_at, client_id, clients(name)')
            .eq('status', 'review').order('submitted_at', { ascending: true }).then(rows).then(function (list) {
              list = list || [];
              return { count: list.length, rows: list.map(function (r) {
                return { name: (r.clients && r.clients.name) || 'Client',
                         meta: [SM && SM.titleOf ? SM.titleOf(r) : r.title,
                                SM && SM.periodWord ? SM.periodWord(r.period_start, r.period_end) : ''].filter(Boolean).join(' · '),
                         fig: 'In review', age: sinceWord(r.submitted_at),
                         url: '/admin/?s=reports&report=' + encodeURIComponent(r.id), section: 'reports' };
              }) };
            });
        } },
      { key: 'noreport', title: function () { return 'No report for ' + lastMonth().word; },
        can: function () { return may('reports', 'manage'); },
        all: ['/admin/?s=reports', 'reports'], empty: 'Every active client has one.',
        load: function () {
          var lm = lastMonth(), ms = lm.start, me = lm.end;
          return Promise.all([
            db.from('clients').select('id, name, slug').eq('stage', 'active').order('name').then(rows),
            db.from('sm_reports').select('client_id, period_start, period_end')
              .lte('period_start', isoDay(me)).gte('period_end', isoDay(ms)).then(rows)
          ]).then(function (r) {
            var has = {};
            (r[1] || []).forEach(function (x) { has[x.client_id] = 1; });
            var none = (r[0] || []).filter(function (c) { return !has[c.id]; });
            return { count: none.length, rows: none.map(function (c) {
              return { name: c.name, meta: '', fig: '', age: '', url: '/admin/?s=reports', section: 'reports' };
            }) };
          });
        } }
    ] },

    { head: 'Team', key: 'team', cards: [
      { key: 'reviews', title: function () { return 'Reviews for ' + lastMonth().word; },
        can: function () { return may('team.performance'); }, empty: 'Every review is final.',
        all: function () { return ['/admin/?s=team&tab=performance&m=' + lastMonth().key, 'team']; },
        load: function () {
          var key = lastMonth().key;
          var P = window.ADspacePerf;
          var words = (P && P.status) || {};
          return db.rpc('perf_overview', { p_period: key + '-01' }).then(rows).then(function (d) {
            var open = (d.rows || []).filter(function (r) { return r.status !== 'final'; });
            return { count: open.length, rows: open.map(function (r) {
              var w = words[r.status] || [r.status === 'none' ? 'Not started' : r.status, ''];
              return { name: r.name, meta: '', fig: w[0], figTone: w[1] === 'is-warn' ? 'warn' : '', age: '',
                       url: '/admin/?s=team&tab=performance&m=' + key, section: 'team' };
            }) };
          });
        } }
    ] }
  ];

  var SHOWN = 5;

  // ---- Drawing ------------------------------------------------------------------
  function listCard(card) {
    var el = document.createElement('article');
    el.className = 'chartcard ovw-card';
    el.setAttribute('data-card', card.key);
    el.innerHTML = '<div class="ovw-cardhead"><h3></h3><span class="ovw-count" hidden></span>' +
      (card.all ? '<button class="btn btn-quiet btn-sm ovgo" type="button" data-a="all"><span class="ovgo-word">View all</span>' + CHEV + '</button>' : '') +
      '</div><div class="ovw-body"></div>';
    el.querySelector('h3').textContent = card.title;
    return el;
  }
  function paintList(el, card, out) {
    el.querySelector('h3').textContent = card.title;
    var all = el.querySelector('[data-a="all"]');
    if (all) all.onclick = function () { go(card.all[0], card.all[1]); };
    var count = el.querySelector('.ovw-count');
    count.hidden = !out.count;
    count.textContent = String(out.count || '');
    count.className = 'ovw-count tone' + (out.count && card.warn ? ' is-warn' : '');
    if (card.onCount) card.onCount(out.count || 0, Boolean(card.warn));
    var body = el.querySelector('.ovw-body');
    if (!out.rows.length) { UI.emptyLine(body, card.empty || 'Nothing waiting.'); return; }
    body.innerHTML = '<div class="ovw-rows">' + out.rows.slice(0, SHOWN).map(function (r, i) {
      return '<button class="ovw-row" type="button" data-i="' + i + '">' +
        '<span class="ovw-who"><b>' + esc(r.name) + '</b>' + (r.meta ? '<small>' + esc(r.meta) + '</small>' : '') + '</span>' +
        ((r.fig || r.age) ? '<span class="ovw-fig">' + (r.fig ? '<b' + (r.figTone ? ' class="is-' + r.figTone + '"' : '') + '>' + esc(r.fig) + '</b>' : '') +
          (r.age ? '<small>' + esc(r.age) + '</small>' : '') + '</span>' : '') +
        '</button>';
    }).join('') + '</div>' +
      (out.rows.length > SHOWN && card.all ? '<p class="ovw-more">' + (out.rows.length - SHOWN) + ' more</p>' : '');
    Array.prototype.forEach.call(body.querySelectorAll('.ovw-row'), function (b) {
      var r = out.rows[Number(b.getAttribute('data-i'))];
      b.addEventListener('click', function () { go(r.url, r.section); });
    });
  }

  function drawCard(grid, spec) {
    /* A title or a way out that names a month is worked out on the visit. */
    var card = Object.assign({}, spec, {
      title: typeof spec.title === 'function' ? spec.title() : spec.title,
      all: typeof spec.all === 'function' ? spec.all() : spec.all
    });
    var el;
    if (card.chart) {
      el = document.createElement('div');
      el.className = 'chartcard ovw-card';
      el.setAttribute('data-card', card.key);
      el.innerHTML = '<h3 class="chart-title"></h3><div class="ovw-body"></div>';
      el.querySelector('h3').textContent = card.title;
    } else {
      el = listCard(card);
    }
    grid.appendChild(el);
    var body = el.querySelector('.ovw-body');
    UI.skeleton(body, 3);
    var run = function () {
      UI.skeleton(body, 3);
      Promise.resolve().then(function () { return card.load(); }).then(function (out) {
        if (!el.isConnected) return;
        if (card.chart) {
          if (out.empty) { UI.emptyLine(body, out.empty); return; }
          var holder = document.createElement('div');
          CH.draw(holder, out);
          var drawn = holder.firstElementChild;
          if (drawn) { drawn.classList.add('ovw-card'); drawn.setAttribute('data-card', card.key); el.replaceWith(drawn); }
          return;
        }
        paintList(el, card, out);
      }).catch(function (e) {
        if (!el.isConnected) return;
        if (!card.chart) el.querySelector('h3').textContent = card.title;
        UI.failLine(body, card.title || 'This card', (e && e.message) || 'The read failed.', run);
      });
    };
    run();
  }

  /* One tab a section, in the rail's order (the user, 2026-10-01: a page
     read section by section, not one long scroll). Each tab carries how
     many items its cards hold waiting, warn where one of them is late, so
     the glance across sections survives in the strip. Every card is read
     once on the visit; a tab only shows its pane. The tab rides in the
     address (`tab=`), the first left out. */
  var shown = null;
  function pick(key, focus) {
    var strip = $('ovwTabs');
    if (!strip) return;
    shown = key;
    Array.prototype.forEach.call(strip.querySelectorAll('.tab'), function (b) {
      var on = b.getAttribute('data-sec') === key;
      b.classList.toggle('is-on', on);
      b.setAttribute('aria-selected', String(on));
      b.tabIndex = on ? 0 : -1;
      if (on && focus) b.focus();
    });
    Array.prototype.forEach.call($('ovwBody').querySelectorAll('.ovw-pane'), function (pn) {
      pn.hidden = pn.getAttribute('data-sec') !== key;
    });
    if (window.ADspaceForm && window.ADspaceForm.thumb) window.ADspaceForm.thumb(strip);
    if (bridge.setUrl) bridge.setUrl();
  }
  function urlState() {
    var strip = $('ovwTabs'), first = strip && strip.querySelector('.tab');
    return { tab: shown && first && shown !== first.getAttribute('data-sec') ? shown : '' };
  }

  function enter() {
    var box = $('ovwBody'), strip = $('ovwTabs');
    if (!box || !strip) return;
    reportP = null;
    box.innerHTML = ''; strip.innerHTML = '';
    var secs = SECTIONS.map(function (sec) {
      return { sec: sec, cards: sec.cards.filter(function (c) { return c.can(); }) };
    }).filter(function (x) { return x.cards.length; });
    strip.hidden = !secs.length;
    secs.forEach(function (x) {
      var tab = document.createElement('button');
      tab.type = 'button'; tab.className = 'tab'; tab.setAttribute('role', 'tab');
      tab.setAttribute('data-sec', x.sec.key);
      tab.id = 'ovwTab-' + x.sec.key;
      tab.setAttribute('aria-controls', 'ovwPane-' + x.sec.key);
      tab.innerHTML = '<span></span><span class="tab-n" hidden></span>';
      tab.firstChild.textContent = x.sec.head;
      strip.appendChild(tab);
      var pane = document.createElement('div');
      pane.className = 'ovw-pane'; pane.id = 'ovwPane-' + x.sec.key;
      pane.setAttribute('role', 'tabpanel'); pane.setAttribute('aria-labelledby', tab.id);
      pane.setAttribute('data-sec', x.sec.key); pane.hidden = true;
      var grid = document.createElement('div');
      grid.className = 'chartgrid ovw-grid';
      pane.appendChild(grid);
      box.appendChild(pane);
      var counts = {};
      var mark = function () {
        var n = 0, late = false;
        Object.keys(counts).forEach(function (k) { n += counts[k].n; if (counts[k].n && counts[k].warn) late = true; });
        var badge = tab.querySelector('.tab-n');
        badge.hidden = !n;
        badge.textContent = String(n);
        badge.classList.toggle('is-warn', late);
      };
      x.cards.forEach(function (c) {
        drawCard(grid, Object.assign({}, c, { onCount: function (n, warn) { counts[c.key] = { n: n, warn: warn }; mark(); } }));
      });
    });
    var want = new URLSearchParams(location.search).get('tab');
    var keys = secs.map(function (x) { return x.sec.key; });
    pick(keys.indexOf(want) > -1 ? want : keys[0]);
  }
  (function wire() {
    var strip = $('ovwTabs');
    if (!strip) return;
    strip.addEventListener('click', function (e) {
      var b = e.target.closest && e.target.closest('.tab');
      if (b) pick(b.getAttribute('data-sec'));
    });
    strip.addEventListener('keydown', function (e) {
      var tabs = Array.prototype.slice.call(strip.querySelectorAll('.tab'));
      var i = tabs.indexOf(document.activeElement);
      if (i < 0) return;
      var to = e.key === 'ArrowRight' ? i + 1 : e.key === 'ArrowLeft' ? i - 1 : e.key === 'Home' ? 0 : e.key === 'End' ? tabs.length - 1 : null;
      if (to === null) return;
      e.preventDefault();
      to = (to + tabs.length) % tabs.length;
      pick(tabs[to].getAttribute('data-sec'), true);
    });
  })();

  window.ADspaceOverview = { enter: enter, urlState: urlState };
  if (bridge.overviewReady) bridge.overviewReady();
})();
