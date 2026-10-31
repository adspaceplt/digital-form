/*
 * Analytics (`?s=analytics`, 2026-10-25) — the past and what to expect next,
 * for decision making (the user, 2026-10-25: "like the dashboard but more
 * detailed about the past and also the future"). Admins only, as a granted
 * part (`team.analytics`); its own section, under the Dashboard.
 *
 * One tab a subject (Sales, Clients) and one period over all of it (Last
 * 12 months by default), each period read against the same span before it,
 * to the same moment. Both are drawn from what every client already carries
 * (its stage history, source, industry and market; `ADspaceSales`), read
 * once a visit. Delivery, content and reports join once they hold enough
 * history to read a trend from (2026-10-25: no tab until then).
 *
 * Months count only from the Business setting `analytics_from` (YYYYMM):
 * before it the portal held clients typed in later, never the leads that
 * came to nothing. A forecast is drawn only where twelve full months are
 * held from it and the period runs to now: the mean of the last six full
 * months, times each month's usual share of the year once twenty-four are
 * held, with one standard deviation of the last twelve as its likely range.
 *
 * Every comparison says whether it moved for the better or the worse
 * (2026-10-25, the user: "i dont see whether this analytics trend is good
 * or bad"): each figure knows the way it should move, and a move under the
 * Business setting `analytics_change_pct` reads Steady; churn a quarter
 * above `analytics_churn_pct` reads Above alert, and each trend says where
 * the last six full months are heading. A dot and its word in ink, never a
 * colour alone (`judge`, `direction`).
 *
 * Write with AI (`analytics-read`) sends the figures worked out here, never
 * a client's name, for a management analysis kept as versions
 * (`analytics_reads`); every number it quotes is checked against them.
 */
(function () {
  var API = window.ADspaceAPI;
  var db = API && API.client;
  var UI = window.ADspaceState;
  var CH = window.ADspaceChart;
  var CK = window.ADspaceClock;
  var bridge = window.ADspaceAdmin || {};
  if (!API || !API.configured || !db || !UI || !CH || !CK) return;
  function S() { return window.ADspaceSales; }

  function $(id) { return document.getElementById(id); }
  function esc(s) { return window.ADspaceWords.esc(s); }
  function may(key, lv) { return Boolean(bridge.may && bridge.may(key, lv || 'view')); }
  function pad2(n) { return String(n).padStart(2, '0'); }
  function plain(n) { return Number(n || 0).toLocaleString('en-GB'); }
  function one(n) { return (Math.round(n * 10) / 10).toLocaleString('en-GB', { maximumFractionDigits: 1 }); }
  function pct(n) { return Math.round(n * 100) + '%'; }
  function monthsWord(n) { return n === 1 ? '1 month' : n + ' months'; }
  function daysWord(n) { return n === 1 ? '1 day' : n + ' days'; }
  function setting(k, d) {
    var M = window.ADspaceMoney, v = M && M.setting ? M.setting(k) : null;
    return v == null || isNaN(Number(v)) ? d : Number(v);
  }
  /* Leads are kept in the portal from the Business setting `analytics_from`
     (Sept 2026): before it the team typed in only the clients it won, never
     the leads that came to nothing (2026-10-25). One source for both, never
     a month typed here (2026-10-27, ANL-1). */
  function leadsFrom() {
    var v = setting('analytics_from', 0);
    return v >= 190001 ? String(Math.floor(v / 100)) + '-' + pad2(v % 100) : '';
  }
  /* A span before that month holds no lost leads, so leads and win rate
     are never judged against it. */
  function leadsComparable(pr) { var k = leadsFrom(); return !k || CK.day(pr.from).slice(0, 7) >= k; }

  // ---- Better or worse -------------------------------------------------------------
  /* A figure against the period before, `good` the way it should move ('up'
     or 'down'): Better or Worse once it moved by the Business setting
     `analytics_change_pct` (10%) and, for a count, by at least `min`; else
     Steady. Nothing to compare reads nothing. */
  function judge(now, before, good, min) {
    if (now == null || before == null || isNaN(now) || isNaN(before)) return null;
    var d = now - before, thr = setting('analytics_change_pct', 10) / 100;
    var rel = before ? Math.abs(d) / Math.abs(before) : (d ? 1 : 0);
    if (!d || rel < thr || (min && Math.abs(d) < min)) return { tone: 'off', word: 'Steady' };
    var ok = good === 'up' ? d > 0 : d < 0;
    return { tone: ok ? 'ok' : 'late', word: ok ? 'Better' : 'Worse' };
  }
  function verdictHtml(v) {
    return v ? '<span class="anl-verdict is-' + v.tone + '">' + esc(v.word) + '</span>' : '';
  }
  /* Clients lost a quarter, as a share of those active at the period's
     start, and whether it passes the alert (`analytics_churn_pct`). */
  function churnOf(f, n) {
    if (!f.activeStart || !n) return null;
    var q = f.churned.length / f.activeStart * 3 / n, alert = setting('analytics_churn_pct', 10) / 100;
    return { rate: q, alert: alert, over: q > alert };
  }
  /* Where the last six full months are heading: the least squares slope
     over them, Rising or Falling once six months of it move the average by
     the change threshold and by one at least (a tenth of a client a month
     is no trend). */
  function direction(h, field, good) {
    var full = fullKeys(h).slice(-6);
    if (full.length < 6) return null;
    var ys = full.map(function (k) { return h.months[k][field] || 0; }), n = ys.length;
    var mx = (n - 1) / 2, my = mean(ys), num = 0, den = 0;
    ys.forEach(function (y, i) { num += (i - mx) * (y - my); den += (i - mx) * (i - mx); });
    var slope = den ? num / den : 0, thr = setting('analytics_change_pct', 10) / 100;
    var moved = Math.abs(slope * (n - 1)), flat = !slope || moved < 1 || (my && moved / my < thr);
    var ok = good === 'up' ? slope > 0 : slope < 0;
    return { slope: slope, tone: flat ? 'off' : ok ? 'ok' : 'late', word: flat ? 'Steady' : slope > 0 ? 'Rising' : 'Falling',
      line: flat ? 'Level across the last 6 full months' : (slope > 0 ? '+' : '−') + one(Math.abs(slope)) + ' a month across the last 6 full months' };
  }
  function directionHtml(list) {
    list = list.filter(function (x) { return x && x.d; });
    return list.length ? '<div class="anl-dirs">' + list.map(function (x) {
      return '<p class="anl-dir"><b>' + esc(x.label) + '</b>' + verdictHtml(x.d) + '<span>' + esc(x.d.line) + '</span></p>';
    }).join('') + '</div>' : '';
  }

  // ---- Who sees what -------------------------------------------------------------
  function allowed() { return may('team.analytics', 'work') && TABS.some(function (t) { return canTab(t[0]); }); }
  var TABS = [['sales', 'Sales'], ['clients', 'Clients']];
  /* Each tab reads only what its sections are held at Full Access, as the
     Dashboard's cards do. */
  function canTab(k) {
    if (k === 'sales') return may('clients', 'manage') && may('clients.leads', 'manage');
    if (k === 'clients') return may('clients', 'manage');
    return false;
  }
  /* A group that sees its own clients alone reads its own figures: said
     once under the bar, so they are never taken for the company's. */
  function ownOnly() {
    var me = bridge.me && bridge.me();
    return Boolean(me && me.client_scope === 'own' && !me.is_admin && me.role !== 'admin');
  }

  // ---- The period ------------------------------------------------------------------
  var PERIODS = [['12', 'Last 12 months'], ['6', 'Last 6 months'], ['24', 'Last 24 months'],
                 ['year', 'This year'], ['lastyear', 'Last year']];
  var period = '12', tab = 'sales';
  function monthStart(key) { return CK.start(key.slice(0, 7) + '-01'); }
  function rangeOf(p) {
    var now = new Date(), t = CK.today();
    if (p === 'year') return { from: monthStart(t.slice(0, 4) + '-01'), to: now, open: true };
    if (p === 'lastyear') {
      var y = Number(t.slice(0, 4)) - 1;
      return { from: monthStart(y + '-01'), to: monthStart((y + 1) + '-01'), open: false };
    }
    var n = Number(p) || 12;
    return { from: monthStart(CK.addMonths(t, -(n - 1))), to: now, open: true };
  }
  /* The period before: the same months a span earlier (Last year the year
     before it, This year the same days of last year). */
  function prevOf(p) {
    var r = rangeOf(p), n = p === 'year' || p === 'lastyear' ? 12 : Number(p) || 12;
    /* The span before ends at the same moment of its own month: a period
       running to now is read against one running to now's day n months
       back, never against whole months (2026-10-25, review 2). */
    return { from: monthStart(CK.addMonths(CK.day(r.from), -n)), to: new Date(shiftMonths(r.to, -n)) };
  }
  /* A moment n months earlier or later, on the same day and time in
     Malaysia (the last day of a shorter month where the day is not held). */
  function shiftMonths(d, n) {
    var day = CK.day(d), key = CK.addMonths(day.slice(0, 7), n);
    var last = Number(CK.addDays(CK.addMonths(key, 1) + '-01', -1).slice(8, 10));
    var p = CK.parts(d);
    return CK.at(key + '-' + pad2(Math.min(p.d, last)), pad2(p.h) + ':' + pad2(p.mi)).getTime();
  }
  /* How many months a range covers, its last one counted as the share of
     it that has passed, so a month is read the same in both spans. */
  function monthsIn(r) {
    var ks = keysOf(r), last = ks[ks.length - 1];
    var a = monthStart(last).getTime(), b = monthStart(CK.addMonths(last, 1)).getTime();
    return ks.length - 1 + Math.max(0, Math.min(1, (r.to.getTime() - a) / (b - a)));
  }
  function prevWord(p) {
    if (p === 'year') return 'the same months last year';
    if (p === 'lastyear') return 'the year before';
    return 'the ' + (Number(p) || 12) + ' months before';
  }
  // The months a range covers, oldest first: 'YYYY-MM'.
  function keysOf(r) {
    var out = [], k = CK.day(r.from).slice(0, 7), end = CK.day(new Date(r.to.getTime() - 1)).slice(0, 7);
    while (k <= end) { out.push(k); k = CK.addMonths(k, 1); }
    return out;
  }
  function monWord(key) { return CK.MON[Number(key.slice(5, 7)) - 1]; }
  function monthLong(key) { return CK.MON[Number(key.slice(5, 7)) - 1] + ' ' + key.slice(0, 4); }
  function spanWord(r) {
    var ks = keysOf(r), a = ks[0], b = ks[ks.length - 1];
    return a === b ? monWord(a) + ' ' + a.slice(0, 4) : monWord(a) + ' ' + a.slice(0, 4) + ' to ' + monWord(b) + ' ' + b.slice(0, 4);
  }

  // ---- Reads, once a visit -----------------------------------------------------------
  var memo = {};
  function once(k, f) { return memo[k] || (memo[k] = f().catch(function (e) { delete memo[k]; throw e; })); }
  function rows(r) {
    if (!r || r.error) throw new Error((r && r.error && r.error.message) || 'The read was refused.');
    return r.data;
  }
  function clients() {
    return once('clients', function () {
      return API.readPages(function () {
        return db.from('clients').select('id, name, slug, stage, stage_reason, stage_log, stage_since, created_at, source, owner, market, industry, bill_sgd').order('id');
      }).then(rows).then(function (l) { return l || []; });
    });
  }

  // ---- Sums by month ---------------------------------------------------------------------
  function firstAt(c) { var m = S().movesOf(c)[0]; return m ? m.at : c.created_at; }
  /* The month the oldest client's history begins, and every month from it to
     now with what happened in it (`ADspaceSales.figures`, one read). */
  function history(cl) {
    var start = null;
    cl.forEach(function (c) { var a = firstAt(c); if (a && (!start || a < start)) start = a; });
    if (!start) return { start: null, months: {}, keys: [] };
    var key0 = CK.day(start).slice(0, 7);
    var f = S().figures(cl, null, { from: monthStart(key0), to: new Date() });
    var out = {}, keys = [], k = key0;
    f.months.forEach(function (m) {
      out[k] = { newLeads: m.newLeads, won: m.won, churned: m.churned, active: m.active };
      keys.push(k); k = CK.addMonths(k, 1);
    });
    return { start: key0, months: out, keys: keys };
  }
  /* The month the history counts from (Business setting `analytics_from`,
     YYYYMM): the later of it and the oldest client's first move. */
  function countsFrom(h) {
    var M = window.ADspaceMoney, v = M && M.setting ? Number(M.setting('analytics_from')) : 0;
    var set = v >= 190001 ? String(Math.floor(v / 100)) + '-' + pad2(v % 100) : '';
    return h.start && h.start > set ? h.start : (set || h.start);
  }
  /* Full months held: every month from the one it counts from to the last
     before this one. */
  function fullKeys(h) {
    var cur = CK.today().slice(0, 7), from = countsFrom(h) || '';
    return h.keys.filter(function (k) { return k < cur && k >= from; });
  }

  // ---- The forecast ------------------------------------------------------------------------
  function mean(a) { return a.length ? a.reduce(function (s, x) { return s + x; }, 0) / a.length : 0; }
  function sd(a) { var m = mean(a); return a.length > 1 ? Math.sqrt(mean(a.map(function (x) { return (x - m) * (x - m); }))) : 0; }
  /* Each calendar month's usual share of the year: its average over the full
     months held against the average of them all; only from 24 months. */
  function seasonOf(h, field) {
    var full = fullKeys(h);
    if (full.length < 24) return null;
    var all = mean(full.map(function (k) { return h.months[k][field]; }));
    var by = [];
    for (var m = 0; m < 12; m++) {
      var v = full.filter(function (k) { return Number(k.slice(5, 7)) - 1 === m; }).map(function (k) { return h.months[k][field]; });
      by.push({ m: m, avg: mean(v), idx: all ? Math.max(.5, Math.min(2, mean(v) / all)) : 1 });
    }
    return { all: all, by: by };
  }
  function forecast(h, field, n) {
    var full = fullKeys(h);
    if (full.length < 12) return null;
    var vals = full.map(function (k) { return h.months[k][field]; });
    var base = mean(vals.slice(-6)), spread = sd(vals.slice(-12)), season = seasonOf(h, field);
    /* From this month, still running, to n months after it. */
    var out = [], k = CK.addMonths(CK.today().slice(0, 7), -1);
    for (var i = 0; i <= n; i++) {
      k = CK.addMonths(k, 1);
      var idx = season ? season.by[Number(k.slice(5, 7)) - 1].idx : 1;
      var v = base * idx;
      out.push({ key: k, value: v, low: Math.max(0, v - spread), high: v + spread });
    }
    return out;
  }

  // ---- Pieces of a page ----------------------------------------------------------------------
  function fail(host, what, e, again) {
    UI.failLine(host, what, (e && e.message) || 'The read failed.', again);
  }
  function tiles(box, list) {
    var wrap = document.createElement('div');
    wrap.className = 'ovw-groups is-one';
    wrap.innerHTML = '<section class="ovw-group"><div class="ovw-kpis"></div></section>';
    box.appendChild(wrap);
    var grid = wrap.querySelector('.ovw-kpis');
    list.forEach(function (t) {
      var el = document.createElement('article');
      el.className = 'chartcard ovw-kpi';
      el.setAttribute('data-tile', t.key);
      el.innerHTML = '<span class="ovw-kpi-label"></span><b class="ovw-kpi-fig"></b><span class="ovw-kpi-sub"></span><span class="ovw-kpi-trend"></span>';
      el.querySelector('.ovw-kpi-label').textContent = t.label;
      el.querySelector('.ovw-kpi-fig').textContent = t.fig;
      el.querySelector('.ovw-kpi-sub').innerHTML = verdictHtml(t.verdict) + esc(t.sub || '');
      if (t.spark && t.spark.length > 1) el.querySelector('.ovw-kpi-trend').innerHTML = CH.spark(t.spark);
      grid.appendChild(el);
    });
  }
  function row(box, lead) {
    var grid = document.createElement('div');
    grid.className = lead ? 'chartgrid anl-lead' : 'chartgrid ovw-grid anl-row';
    box.appendChild(grid);
    return grid;
  }
  function cardhead(title, aside) {
    return '<div class="ovw-cardhead"><h3>' + esc(title) + '</h3>' + (aside ? '<span class="anl-aside">' + esc(aside) + '</span>' : '') + '</div>';
  }
  /* A chart drawn in a card of its own, its title and an aside at its head. */
  function chart(grid, key, title, spec, aside, after) {
    var holder = document.createElement('div');
    spec.title = title;
    CH.draw(holder, spec);
    var el = holder.firstElementChild;
    el.classList.add('ovw-card');
    el.setAttribute('data-card', key);
    var h = el.querySelector('.chart-title');
    if (h) {
      var tmp = document.createElement('div');
      tmp.innerHTML = cardhead(title, aside);
      h.replaceWith(tmp.firstChild);
    }
    if (after) {
      var note = document.createElement('p');
      note.className = 'anl-note';
      note.textContent = after;
      var data = el.querySelector('.chart-data');
      if (data) el.insertBefore(note, data); else el.appendChild(note);
    }
    grid.appendChild(el);
    return el;
  }
  function card(grid, key, title, aside, html) {
    var el = document.createElement('section');
    el.className = 'chartcard ovw-card';
    el.setAttribute('data-card', key);
    el.innerHTML = cardhead(title, aside) + '<div class="ovw-body">' + html + '</div>';
    grid.appendChild(el);
    return el;
  }
  /* What a section still needs before its trend is read: the months held
     against the months asked, and when the rest arrive. */
  function waitHtml(title, held, need, line) {
    var w = Math.max(0, Math.min(1, held / need));
    return '<div class="anl-wait"><div class="anl-wait-words"><b>' + esc(title) + '</b><span>' + esc(line) + '</span></div>' +
      '<div class="anl-wait-bar"><span>' + esc(held + ' of ' + need + ' months') + '</span>' +
      '<span class="ovw-kpi-bar" aria-hidden="true"><i style="width:' + Math.round(w * 100) + '%"></i></span></div></div>';
  }
  function changeWord(now, before, digits) {
    var d = now - before;
    if (!d) return 'Level with ' + prevWord(period);
    var f = digits ? one(Math.abs(d)) : plain(Math.abs(d));
    return (d > 0 ? '+' : '−') + f + ' on ' + prevWord(period);
  }

  // ---- Sales ---------------------------------------------------------------------------------
  function leadsLost(f) {
    var out = {};
    f.lost.forEach(function (c) {
      var mv = S().movesOf(c).filter(function (m) { return m.to === 'past'; });
      var k = (mv.length ? mv[mv.length - 1].reason : '') || '';
      out[k] = (out[k] || 0) + 1;
    });
    return out;
  }
  function everActive(c) { return S().movesOf(c).some(function (m) { return m.to === 'active'; }); }
  function winRate(f) { var d = f.won.length + f.lost.length; return d ? { rate: f.won.length / d, won: f.won.length, decided: d } : null; }

  function sales(box, cl) {
    var r = rangeOf(period), pr = prevOf(period);
    var f = S().figures(cl, null, r), fp = S().figures(cl, null, pr);
    var h = history(cl), keys = keysOf(r);
    var per = function (k, fld) { return (h.months[k] || {})[fld] || 0; };
    var n = monthsIn(r), np = monthsIn(pr);
    var lead = f.newLeads.length / n, leadP = fp.newLeads.length / np;
    var wr = winRate(f), wrP = winRate(fp);
    var ch = churnOf(f, n), cmp = leadsComparable(pr);
    if (!cmp) {
      var note = document.createElement('p');
      note.className = 'anl-own anl-from';
      note.textContent = 'Leads are counted from ' + monthLong(leadsFrom()) + '.';
      box.appendChild(note);
    }
    tiles(box, [
      { key: 'leads', label: 'New leads a month', fig: one(lead), sub: cmp ? changeWord(lead, leadP, true) : '',
        verdict: cmp ? judge(f.newLeads.length, fp.newLeads.length, 'up', 2) : null,
        spark: keys.map(function (k) { return per(k, 'newLeads'); }) },
      { key: 'win', label: 'Win rate', fig: wr ? pct(wr.rate) : '—',
        verdict: cmp && wr && wrP && wr.decided >= 3 && wrP.decided >= 3 ? judge(wr.rate, wrP.rate, 'up') : null,
        sub: wr ? wr.won + ' of ' + wr.decided + ' leads decided' + (cmp && wrP ? ' · ' + pct(wrP.rate) + ' before' : '') : 'No lead decided in the period' },
      { key: 'toclient', label: 'Lead to client', fig: f.medianToWin == null ? '—' : daysWord(f.medianToWin),
        verdict: f.won.length >= 3 && fp.won.length >= 3 ? judge(f.medianToWin, fp.medianToWin, 'down') : null,
        sub: 'Median' + (fp.medianToWin == null ? '' : ' · ' + daysWord(fp.medianToWin) + ' before') },
      lostTile(f, fp, ch, keys, per)
    ]);

    var g1 = row(box, true);
    trendCard(g1, h, keys, r);
    insights(g1, clientChanges(f, fp, n).filter(function (x) { return x.verdict && x.verdict.tone === 'late'; }).concat(salesChanges(f, fp, h, cmp)));

    var g2 = row(box);
    season(g2, h);

    var g3 = row(box);
    var src = Object.keys(f.bySource).map(function (k) {
      var list = f.bySource[k], won = list.filter(everActive).length;
      return { label: srcWord(k), value: list.length, won: won };
    }).sort(function (a, b) { return b.value - a.value || a.label.localeCompare(b.label); });
    chart(g3, 'sources', 'Where leads come from', {
      kind: 'bars', inline: true, empty: 'No new leads in the period.',
      rows: src.map(function (s) { return { label: s.label, value: s.value, note: s.won + ' won · ' + pct(s.won / s.value) }; }),
      table: { heads: ['Source', 'Leads', 'Won', 'Win rate'], rows: src.map(function (s) { return [s.label, plain(s.value), plain(s.won), pct(s.won / s.value)]; }) }
    }, spanWord(r));
    var lost = leadsLost(f);
    var lr = Object.keys(lost).map(function (k) { return { label: S().reasonWord(k), value: lost[k] }; })
      .sort(function (a, b) { return b.value - a.value; });
    chart(g3, 'lost', 'Why leads were lost', { kind: 'bars', inline: true, rows: lr, empty: 'No lead was lost in the period.' }, spanWord(r));
  }

  /* Clients lost, judged on the period before and on the churn alert: churn
     above it reads Above alert whatever the count did. */
  /* A source reads as Clients names it (Referral, Walk-in), never its key. */
  function srcWord(k) { var C = window.ADspaceCRM; return C && C.sourceWord ? C.sourceWord(k) : k; }

  function lostTile(f, fp, ch, keys, per) {
    return { key: 'lost', label: 'Clients lost', fig: plain(f.churned.length),
      verdict: ch && ch.over ? { tone: 'late', word: 'Above alert' } : judge(f.churned.length, fp.churned.length, 'down', 2),
      sub: (ch ? 'Churn ' + pct(ch.rate) + ' a quarter, alert ' + pct(ch.alert) + ' · ' : '') + plain(fp.churned.length) + ' before',
      spark: keys.map(function (k) { return per(k, 'churned'); }) };
  }

  function trendCard(grid, h, keys, r) {
    var fl = r.open ? forecast(h, 'newLeads', 3) : null, fw = fl ? forecast(h, 'won', 3) : null;
    var cats = keys.map(function (k) {
      var m = h.months[k] || {};
      return { label: monWord(k), long: monthLong(k), values: [m.newLeads || 0, m.won || 0, null, null] };
    });
    var series = [{ label: 'New leads' }, { label: 'New clients', tone: 'mute' }];
    var band = null, note = '', aside = '';
    var full = fullKeys(h).length;
    if (fl) {
      /* The line of what happened ends at the last full month; the month
         still running is the forecast's first point, its count so far in
         its name, so a part month never reads as a fall (review 8). */
      var r1 = function (v) { return Math.round(v * 10) / 10; };
      var lastFull = cats[cats.length - 2], now = cats[cats.length - 1];
      band = cats.map(function () { return null; });
      if (lastFull) {
        lastFull.values[2] = lastFull.values[0]; lastFull.values[3] = lastFull.values[1];
        band[band.length - 2] = [lastFull.values[0], lastFull.values[0]];
      }
      now.long = now.long + ' (forecast; ' + plain(now.values[0]) + ' so far)';
      now.values = [null, null, r1(fl[0].value), r1(fw[0].value)];
      band[band.length - 1] = [r1(fl[0].low), r1(fl[0].high)];
      fl.slice(1).forEach(function (x, i) {
        cats.push({ label: monWord(x.key), long: monthLong(x.key) + ' (forecast)', values: [null, null, r1(x.value), r1(fw[i + 1].value)] });
        band.push([r1(x.low), r1(x.high)]);
      });
      series.push({ label: 'Forecast: leads', dash: true }, { label: 'Forecast: new clients', tone: 'mute', dash: true });
      var ahead = fl.slice(1), wa = fw.slice(1), endK = ahead[ahead.length - 1].key;
      var lo = Math.round(Math.min.apply(null, ahead.map(function (x) { return x.low; })));
      var hi = Math.round(Math.max.apply(null, ahead.map(function (x) { return x.high; })));
      var wl = Math.round(Math.min.apply(null, wa.map(function (x) { return x.low; })));
      var wh = Math.round(Math.max.apply(null, wa.map(function (x) { return x.high; })));
      note = monWord(ahead[0].key) + ' to ' + monWord(endK) + ' expected: ' + lo + ' to ' + hi + ' leads a month, ' + wl + ' to ' + wh +
        ' new clients. From the average of the last 6 full months' + (seasonOf(h, 'newLeads') ? ' and each month\'s usual share of the year.' : '.');
      aside = 'Forecast to ' + monWord(endK) + ' ' + endK.slice(0, 4);
    } else if (r.open) {
      aside = full >= 12 ? '' : 'Forecast from ' + monthLong(CK.addMonths(countsFrom(h) || CK.today().slice(0, 7), 12));
      if (full < 12) note = 'A forecast is shown once 12 full months of data are available. ' + monthsWord(full) + (full === 1 ? ' is' : ' are') + ' held.';
    }
    var el = chart(grid, 'trend', 'Leads and new clients by month', {
      kind: 'line', cats: cats, series: series, band: band, bandWord: band ? 'Likely range' : '', none: 'No figure'
    }, aside, note);
    el.classList.add('anl-trend');
    heading(el, [{ label: 'New leads', d: direction(h, 'newLeads', 'up') }, { label: 'New clients', d: direction(h, 'won', 'up') }]);
  }
  /* Where a chart's figures are heading, under its title. */
  function heading(el, list) {
    var html = directionHtml(list);
    if (!html) return;
    var tmp = document.createElement('div');
    tmp.innerHTML = html;
    var head = el.querySelector('.ovw-cardhead');
    if (head) head.after(tmp.firstChild); else el.insertBefore(tmp.firstChild, el.firstChild);
  }

  /* What changed: rules over the figures, the worst and largest first, five
     at most. Each finding knows the way it should move (`good`) and says
     Better, Worse or Steady beside its figure; one that is only a fact
     (the busiest month) says neither. */
  function salesChanges(f, fp, h, cmp) {
    var out = [];
    var a = f.newLeads.length, b = fp.newLeads.length;
    if (cmp !== false && Math.max(a, b) >= 3 && b && Math.abs(a - b) / b >= .2) {
      out.push({ w: Math.abs(a - b) / b, dir: a > b ? 'up' : 'down', verdict: judge(a, b, 'up', 2), title: 'New leads',
        sub: a + ' in the period, against ' + b + ' in ' + prevWord(period), value: (a > b ? '+' : '−') + Math.round(Math.abs(a - b) / b * 100) + '%' });
    }
    var srcs = {};
    Object.keys(f.bySource).forEach(function (k) { srcs[k] = 1; });
    Object.keys(fp.bySource).forEach(function (k) { srcs[k] = 1; });
    Object.keys(srcs).forEach(function (k) {
      var x = (f.bySource[k] || []).length, y = (fp.bySource[k] || []).length;
      /* An unrecorded source, or one holding every lead, only repeats New
         leads (2026-10-27, ANL-2). */
      if (cmp === false || !k || k === 'Not recorded' || (x === a && y === b)) return;
      if (Math.max(x, y) < 3 || Math.abs(x - y) < 2) return;
      var ch = y ? (x - y) / y : 1;
      if (Math.abs(ch) < .5) return;
      out.push({ w: Math.abs(ch) * .9, dir: x > y ? 'up' : 'down', verdict: judge(x, y, 'up', 2),
        title: x || !y ? 'Leads from ' + k : 'Leads from ' + k + ' stopped',
        sub: x + ' in the period, against ' + y + ' in ' + prevWord(period), value: y ? (x > y ? '+' : '−') + Math.round(Math.abs(ch) * 100) + '%' : 'New' });
    });
    var wr = winRate(f), wp = winRate(fp);
    if (cmp !== false && wr && wp && wr.decided >= 3 && wp.decided >= 3 && Math.abs(wr.rate - wp.rate) >= .1) {
      out.push({ w: Math.abs(wr.rate - wp.rate) * 2, dir: wr.rate > wp.rate ? 'up' : 'down', verdict: judge(wr.rate, wp.rate, 'up'), title: 'Win rate',
        sub: wr.won + ' of ' + wr.decided + ' decided, against ' + wp.won + ' of ' + wp.decided, value: pct(wr.rate) });
    }
    if (f.medianToWin != null && fp.medianToWin != null && f.won.length >= 3 && fp.won.length >= 3 && fp.medianToWin &&
        Math.abs(f.medianToWin - fp.medianToWin) / fp.medianToWin >= .2) {
      out.push({ w: Math.abs(f.medianToWin - fp.medianToWin) / fp.medianToWin * .8, dir: f.medianToWin < fp.medianToWin ? 'down' : 'up',
        verdict: judge(f.medianToWin, fp.medianToWin, 'down'),
        title: 'Days from lead to client', sub: 'Median ' + daysWord(f.medianToWin) + ', against ' + daysWord(fp.medianToWin), value: daysWord(f.medianToWin) });
    }
    var lost = leadsLost(f), nl = f.lost.length;
    if (nl >= 3) {
      var top = Object.keys(lost).sort(function (x, y) { return lost[y] - lost[x]; })[0];
      if (lost[top] / nl >= .4) out.push({ w: lost[top] / nl * .7, dir: '', title: 'Leads lost on ' + S().reasonWord(top).toLowerCase(),
        sub: lost[top] + ' of ' + nl + ' lost leads', value: pct(lost[top] / nl) });
    }
    var se = seasonOf(h, 'newLeads');
    if (se && se.all) {
      var peak = se.by.slice().sort(function (x, y) { return y.avg - x.avg; })[0];
      if (peak.avg / se.all >= 1.2) out.push({ w: .3, dir: '', title: CK.LONG[peak.m] + ' is the busiest month for leads',
        sub: one(peak.avg) + ' a month on average, against ' + one(se.all) + ' across the year', value: CK.MON[peak.m] });
    }
    return out;
  }
  /* What changed among clients: churn over its alert first, more leaving
     than joining, clients joined and lost on the period before, and an
     industry most of those who left came from. */
  function clientChanges(f, fp, n) {
    var out = [], ch = churnOf(f, n), won = f.won.length, left = f.churned.length;
    if (ch && ch.over) out.push({ w: 3, dir: 'up', verdict: { tone: 'late', word: 'Above alert' }, title: 'Churn above the alert',
      sub: left + ' of ' + f.activeStart + ' active clients left; the alert is ' + pct(ch.alert) + ' a quarter', value: pct(ch.rate) + ' a quarter' });
    if (left > won && left >= 2) out.push({ w: 2.5, dir: 'down', verdict: { tone: 'late', word: 'Worse' }, title: 'More clients left than joined',
      sub: won + ' joined, ' + left + ' left', value: '−' + (left - won) + ' net' });
    var vl = judge(left, fp.churned.length, 'down', 2);
    if (vl && vl.word !== 'Steady') out.push({ w: 1.5, dir: left > fp.churned.length ? 'up' : 'down', verdict: vl, title: 'Clients lost',
      sub: left + ' in the period, against ' + fp.churned.length + ' in ' + prevWord(period), value: plain(left) });
    var vw = judge(won, fp.won.length, 'up', 2);
    if (vw && vw.word !== 'Steady') out.push({ w: 1.2, dir: won > fp.won.length ? 'up' : 'down', verdict: vw, title: 'Clients joined',
      sub: won + ' in the period, against ' + fp.won.length + ' in ' + prevWord(period), value: plain(won) });
    if (left >= 3) {
      var by = {};
      f.churned.forEach(function (c) { var k = c.industry || 'Not recorded'; by[k] = (by[k] || 0) + 1; });
      var top = Object.keys(by).sort(function (x, y) { return by[y] - by[x]; })[0];
      if (top !== 'Not recorded' && by[top] >= 2 && by[top] / left >= .4) out.push({ w: 1.4, dir: '', verdict: { tone: 'late', word: 'Worse' },
        title: 'Clients lost in ' + top, sub: by[top] + ' of ' + left + ' clients who left', value: pct(by[top] / left) });
    }
    return out;
  }
  var ARROW = { up: '↑', down: '↓', '': '·' };
  function insights(grid, out) {
    out.sort(function (x, y) { return y.w - x.w; });
    var html = out.length ? '<div class="anl-ins">' + out.slice(0, 5).map(function (x) {
      var t = x.verdict ? x.verdict.tone : '';
      return '<div class="anl-ins-row"><span class="anl-ins-dir' + (t ? ' is-' + t : '') + '" aria-hidden="true">' + ARROW[x.dir] + '</span>' +
        '<span class="anl-ins-what"><b>' + esc(x.title) + '</b><small>' + esc(x.sub) + '</small></span>' +
        '<span class="anl-ins-val">' + esc(x.value) + verdictHtml(x.verdict) + '</span></div>';
    }).join('') + '</div>' : '<div class="softpanel"><div class="emptyline"><b>No change large enough to show.</b></div></div>';
    card(grid, 'changed', 'What changed', 'On ' + prevWord(period), html).classList.add('anl-changed');
  }

  /* Each calendar month's average new leads, from 24 full months; until
     then, how many are held. */
  function season(grid, h) {
    var se = seasonOf(h, 'newLeads'), full = fullKeys(h).length;
    if (!se) {
      card(grid, 'season', 'Busiest months for new leads', '',
        waitHtml('Busiest months are shown once 24 full months of leads are available',
          full, 24, full ? 'Leads are counted from ' + monthLong(countsFrom(h)) + '. The months show in ' + monthLong(CK.addMonths(countsFrom(h), 24)) + '.' : 'No lead is held yet.'));
      return;
    }
    var sorted = se.by.map(function (x) { return x.avg; }).slice().sort(function (a, b) { return a - b; });
    var level = function (v) {
      if (v === sorted[11]) return 4;
      var q = sorted.indexOf(v) / 11;
      return q >= .75 ? 3 : q >= .5 ? 2 : q >= .25 ? 1 : 0;
    };
    var ranked = se.by.slice().sort(function (x, y) { return y.avg - x.avg; });
    var quiet = se.by.slice().sort(function (x, y) { return x.avg - y.avg; });
    var html = '<div class="anl-season">' + se.by.map(function (x) {
      return '<div class="anl-mon l' + level(x.avg) + '"><span>' + CK.MON[x.m] + '</span><b>' + one(x.avg) + '</b></div>';
    }).join('') + '</div><p class="anl-note">Busiest: ' + CK.LONG[ranked[0].m] + ', then ' + CK.LONG[ranked[1].m] + ' and ' + CK.LONG[ranked[2].m] +
      '. Quietest: ' + CK.LONG[quiet[0].m] + ' and ' + CK.LONG[quiet[1].m] + '.</p>';
    var full0 = fullKeys(h);
    card(grid, 'season', 'Busiest months for new leads', 'Average a month, ' + monthLong(full0[0]) + ' to ' + monthLong(full0[full0.length - 1]), html);
  }

  // ---- Clients ----------------------------------------------------------------------------------
  function sinceActive(c) {
    var m = S().movesOf(c).filter(function (x) { return x.to === 'active'; })[0];
    return m ? Math.max(0, CK.between(CK.day(m.at), CK.today())) : null;
  }
  function groupCount(list, f) {
    var out = {};
    list.forEach(function (c) { var k = f(c) || 'Not recorded'; out[k] = (out[k] || 0) + 1; });
    return Object.keys(out).map(function (k) { return { label: k, value: out[k] }; })
      .sort(function (a, b) { return b.value - a.value || a.label.localeCompare(b.label); });
  }
  var MARKET = { MY: 'Malaysia', SG: 'Singapore' };
  function clientsTab(box, cl) {
    var r = rangeOf(period), pr = prevOf(period);
    var f = S().figures(cl, null, r), fp = S().figures(cl, null, pr);
    var h = history(cl), keys = keysOf(r);
    var per = function (k, fld) { return (h.months[k] || {})[fld] || 0; };
    var ten = f.activeEndList.map(sinceActive).filter(function (x) { return x != null; }).sort(function (a, b) { return a - b; });
    var med = ten.length ? ten[Math.floor((ten.length - 1) / 2)] : null;
    var n = monthsIn(r), ch = churnOf(f, n);
    var lt = lostTile(f, fp, ch, keys, per);
    lt.key = 'left'; lt.label = 'Clients left';
    tiles(box, [
      { key: 'active', label: 'Active clients', fig: plain(f.activeEnd), sub: plain(f.activeStart) + ' at the start of ' + monthLong(keys[0]),
        verdict: judge(f.activeEnd, f.activeStart, 'up', 2),
        spark: keys.map(function (k) { return per(k, 'active'); }) },
      { key: 'joined', label: 'Clients joined', fig: plain(f.won.length), sub: plain(fp.won.length) + ' in ' + prevWord(period),
        verdict: judge(f.won.length, fp.won.length, 'up', 2),
        spark: keys.map(function (k) { return per(k, 'won'); }) },
      lt,
      { key: 'tenure', label: 'Time as a client', fig: med == null ? '—' : monthsWord(Math.round(med / 30.4)), sub: 'Median of active clients' }
    ]);
    var cur = CK.today().slice(0, 7);
    var g1 = row(box, true);
    var ac = chart(g1, 'active', 'Active clients by month', {
      kind: 'columns', labels: true,
      cats: keys.map(function (k) { return { label: monWord(k), long: monthLong(k), values: [per(k, 'active')], tone: k === cur ? 'mute' : '' }; }),
      series: [{ label: 'Active clients' }]
    }, spanWord(r));
    heading(ac, [{ label: 'Active clients', d: direction(h, 'active', 'up') }]);
    insights(g1, clientChanges(f, fp, n));
    var g0 = row(box);
    var fl = chart(g0, 'flow', 'Clients joined and left', {
      kind: 'line', cats: keys.map(function (k) { return { label: monWord(k), long: monthLong(k), values: [per(k, 'won'), per(k, 'churned')] }; }),
      series: [{ label: 'Joined' }, { label: 'Left', tone: 'mute' }]
    }, spanWord(r));
    heading(fl, [{ label: 'Joined', d: direction(h, 'won', 'up') }, { label: 'Left', d: direction(h, 'churned', 'down') }]);
    var g2 = row(box);
    chart(g2, 'industry', 'Active clients by industry', { kind: 'bars', inline: true, rows: groupCount(f.activeEndList, function (c) { return c.industry; }), empty: 'No active client.' }, 'Now');
    chart(g2, 'market', 'Active clients by market', { kind: 'bars', inline: true,
      rows: groupCount(f.activeEndList, function (c) { var m = String(c.market || '').toUpperCase(); return MARKET[m] || m; }), empty: 'No active client.' }, 'Now');
    var g3 = row(box);
    var why = Object.keys(f.reasons).map(function (k) {
      var x = f.reasons[k];
      return { label: S().reasonWord(k), value: x.paused.length + x.past.length, note: [x.past.length ? x.past.length + ' left' : '', x.paused.length ? x.paused.length + ' paused' : ''].filter(Boolean).join(' · ') };
    }).sort(function (a, b) { return b.value - a.value; });
    chart(g3, 'why', 'Why clients paused or left', { kind: 'bars', inline: true, rows: why, empty: 'No client paused or left in the period.' }, spanWord(r));
    var BANDS = [['Under 3 months', 0, 91], ['3 to 6 months', 91, 183], ['6 to 12 months', 183, 365], ['1 to 2 years', 365, 730], ['Over 2 years', 730, 1e9]];
    chart(g3, 'stay', 'How long active clients have stayed', { kind: 'bars', inline: true, empty: 'No active client.',
      rows: BANDS.map(function (b) { return { label: b[0], value: ten.filter(function (d) { return d >= b[1] && d < b[2]; }).length }; }) }, 'Now');
  }

  // ---- The AI analysis ------------------------------------------------------------------------
  /* Write with AI (2026-10-25, the user: "could u use AI to do analytics
     deep analysis and reporting"): the figures worked out here for the
     period on show, both tabs' alike, go to `analytics-read`, which answers
     a health read, the risks, what works, the forecast's credibility and
     the actions, kept as the next version. One card above each tab, the
     latest version read first; Versions, Download and Delete in its ⋯. */
  var AI = window.ADspaceConfirm && window.ADspaceConfirm.ai;
  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/></svg>';
  var HEALTH = { good: ['ok', 'Good'], mixed: ['wait', 'Mixed'], poor: ['late', 'Poor'] };
  var SEVERITY = { high: ['late', 'High risk'], medium: ['wait', 'Medium risk'], low: ['off', 'Low risk'] };
  var CREDIBLE = { credible: 'Credible', partly: 'Partly credible', not_credible: 'Not credible', not_drawn: 'Not drawn' };
  var AI_SAID = {
    denied: 'You do not have access to Analytics. Please ask an admin.', 'ai-not-set-up': 'Write with AI is not set up yet. Please contact an admin.',
    'ai-key': 'Write with AI is not available at the moment. Please contact an admin.', 'ai-busy': 'The AI service is busy. Try again in a minute.',
    'ai-credit': 'Write with AI is not available at the moment. Please contact an admin.', 'ai-model': 'Write with AI is not available at the moment. Please contact an admin.',
    'ai-slow': 'The analysis took too long. Try again.', 'ai-incomplete': 'The analysis came back incomplete. Try again.',
    'ai-failed': 'The analysis could not be written. Try again.', 'needs-update': 'This feature is not available yet. Please contact an admin.',
    'bad-analysis': 'The analysis could not be kept. Try again.', 'not-found': 'This version was deleted in the meantime.'
  };
  function aiSaid(e, d) {
    var k = (d && d.error) || (e && e.message) || '';
    if (k === 'ai-limit') return d && d.limit === 0 ? 'Write with AI on Analytics is turned off for you. An admin can turn it on.'
      : 'No analyses left today. The next is free at 12:00 am.';
    if (/function|schema cache|Failed to send/i.test(k)) return 'This feature is not available yet. Please contact an admin.';
    return AI_SAID[k] || 'The analysis could not be written. Try again.';
  }
  function reads() {
    return once('reads', function () {
      return db.rpc('analytics_reads_list').then(function (r) {
        if (r.error || (r.data && r.data.error)) throw new Error((r.error && r.error.message) || r.data.error);
        return (r.data && r.data.versions) || [];
      });
    });
  }
  var shown = null;
  /* The figures as they are sent: what the page shows for the period, the
     period before and the page's own verdicts, never a client's name. */
  function figuresOf(cl) {
    var r = rangeOf(period), pr = prevOf(period);
    var f = S().figures(cl, null, r), fp = S().figures(cl, null, pr);
    var h = history(cl), n = monthsIn(r), np = monthsIn(pr), ch = churnOf(f, n), chp = churnOf(fp, np);
    var wr = winRate(f), wp = winRate(fp);
    var w = function (v) { return v ? v.word : null; };
    var r1 = function (v) { return v == null ? null : Math.round(v * 10) / 10; };
    var pc = function (v) { return v == null ? null : Math.round(v * 1000) / 10; };
    /* The change in whole percent, so the analysis quotes it rather than
       working out its own. */
    var chg = function (a, b) { return b ? Math.round((a - b) / b * 100) : null; };
    var src = Object.keys(f.bySource).concat(Object.keys(fp.bySource)).filter(function (k, i, a) { return a.indexOf(k) === i; }).map(function (k) {
      var list = f.bySource[k] || [];
      return { source: k, leads: list.length, won: list.filter(everActive).length, leads_before: (fp.bySource[k] || []).length };
    });
    var lost = leadsLost(f);
    var why = Object.keys(f.reasons).map(function (k) { var x = f.reasons[k]; return { reason: S().reasonWord(k), left: x.past.length, paused: x.paused.length }; });
    var ten = f.activeEndList.map(sinceActive).filter(function (x) { return x != null; }).sort(function (a, b) { return a - b; });
    var count = function (list, fn) { return groupCount(list, fn).map(function (x) { return { name: x.label, clients: x.value }; }); };
    var dir = function (field, good) { var d = direction(h, field, good); return d ? { heading: d.word, a_month: r1(d.slope) } : null; };
    var fl = rangeOf(period).open ? forecast(h, 'newLeads', 3) : null, fw = fl ? forecast(h, 'won', 3) : null;
    var ahead = fl ? fl.slice(1) : [], wa = fw ? fw.slice(1) : [];
    var lo = function (a, k) { return Math.round(Math.min.apply(null, a.map(function (x) { return x[k]; }))); };
    var hi = function (a, k) { return Math.round(Math.max.apply(null, a.map(function (x) { return x[k]; }))); };
    return {
      period: spanWord(r), compared_with: spanWord(pr), leads_complete_from: leadsFrom() ? monthLong(leadsFrom()) : null,
      counted_from: countsFrom(h) ? monthLong(countsFrom(h)) : null, full_months_held: fullKeys(h).length,
      thresholds: { change_pct: setting('analytics_change_pct', 10), churn_alert_pct_a_quarter: setting('analytics_churn_pct', 10) },
      sales: {
        new_leads: { now: f.newLeads.length, before: fp.newLeads.length, change_pct: chg(f.newLeads.length, fp.newLeads.length), a_month_now: r1(f.newLeads.length / n), a_month_before: r1(fp.newLeads.length / np),
          verdict: w(judge(f.newLeads.length, fp.newLeads.length, 'up', 2)) },
        win_rate_pct: { now: wr ? pc(wr.rate) : null, before: wp ? pc(wp.rate) : null, won: wr ? wr.won : 0, decided: wr ? wr.decided : 0,
          verdict: wr && wp && wr.decided >= 3 && wp.decided >= 3 ? w(judge(wr.rate, wp.rate, 'up')) : null },
        median_days_lead_to_client: { now: f.medianToWin, before: fp.medianToWin,
          verdict: f.won.length >= 3 && fp.won.length >= 3 ? w(judge(f.medianToWin, fp.medianToWin, 'down')) : null },
        leads_lost: { now: f.lost.length, before: fp.lost.length },
        sources: src,
        lost_reasons: Object.keys(lost).map(function (k) { return { reason: S().reasonWord(k), leads: lost[k] }; })
      },
      clients: {
        active: { at_start: f.activeStart, now: f.activeEnd, verdict: w(judge(f.activeEnd, f.activeStart, 'up', 2)) },
        joined: { now: f.won.length, before: fp.won.length, change_pct: chg(f.won.length, fp.won.length), verdict: w(judge(f.won.length, fp.won.length, 'up', 2)) },
        left: { now: f.churned.length, before: fp.churned.length, change_pct: chg(f.churned.length, fp.churned.length), verdict: w(judge(f.churned.length, fp.churned.length, 'down', 2)) },
        churn_pct_a_quarter: { now: ch ? pc(ch.rate) : null, before: chp ? pc(chp.rate) : null, above_alert: !!(ch && ch.over) },
        why_paused_or_left: why,
        left_by_industry: count(f.churned, function (c) { return c.industry; }),
        active_by_industry: count(f.activeEndList, function (c) { return c.industry; }),
        active_by_market: count(f.activeEndList, function (c) { var m = String(c.market || '').toUpperCase(); return MARKET[m] || m; }),
        median_months_as_client: ten.length ? Math.round(ten[Math.floor((ten.length - 1) / 2)] / 30.4) : null
      },
      heading: { new_leads: dir('newLeads', 'up'), new_clients: dir('won', 'up'), active: dir('active', 'up'), left: dir('churned', 'down') },
      months: keysOf(r).map(function (k) {
        var m = h.months[k] || {};
        return { month: monthLong(k), new_leads: m.newLeads || 0, new_clients: m.won || 0, left: m.churned || 0, active: m.active || 0 };
      }),
      forecast: fl ? { months: monthLong(ahead[0].key) + ' to ' + monthLong(ahead[ahead.length - 1].key),
        new_leads_a_month_low: lo(ahead, 'low'), new_leads_a_month_high: hi(ahead, 'high'),
        new_clients_a_month_low: lo(wa, 'low'), new_clients_a_month_high: hi(wa, 'high'),
        basis: 'Average of the last 6 full months' + (seasonOf(h, 'newLeads') ? ' and each month\'s usual share of the year' : '') } : null
    };
  }
  function dot(t) { return '<span class="anl-verdict is-' + t[0] + '">' + esc(t[1]) + '</span>'; }
  function readHtml(v) {
    var a = v.analysis || {}, hl = HEALTH[a.health] || HEALTH.mixed;
    var list = function (title, rows, fn) {
      return rows && rows.length ? '<section class="anl-ai-sec"><h4 class="fsec-h">' + esc(title) + '</h4>' + rows.map(fn).join('') + '</section>' : '';
    };
    return '<p class="anl-ai-health"><b>Health</b>' + dot(hl) + '</p>' +
      '<p class="anl-ai-headline">' + esc(a.headline) + '</p><p class="anl-ai-summary">' + esc(a.summary) + '</p>' +
      '<details class="anl-ai-more"><summary><span>Risks, what is working and actions</span>' +
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg></summary>' +
      list('Risks', a.risks, function (x) {
        return '<div class="anl-ai-row anl-ai-risk"><p><b>' + esc(x.title) + '</b></p>' + dot(SEVERITY[x.severity] || SEVERITY.medium) + '<p>' + esc(x.detail) + '</p></div>';
      }) +
      list('What is working', a.working, function (x) { return '<div class="anl-ai-row"><p><b>' + esc(x.title) + '</b></p><p>' + esc(x.detail) + '</p></div>'; }) +
      (a.forecast ? '<section class="anl-ai-sec"><h4 class="fsec-h">Forecast</h4><div class="anl-ai-row"><p><b>' + esc(CREDIBLE[a.forecast.verdict] || '') + '</b></p>' +
        (a.forecast.detail ? '<p>' + esc(a.forecast.detail) + '</p>' : '') + '</div></section>' : '') +
      (a.actions && a.actions.length ? '<section class="anl-ai-sec"><h4 class="fsec-h">Recommended actions</h4><ol class="anl-ai-acts-list">' +
        a.actions.map(function (x) { return '<li><b>' + esc(x.action) + '</b><span>' + esc(x.why) + '</span></li>'; }).join('') + '</ol></section>' : '') +
      list('Caveats', a.caveats, function (x) { return '<p class="anl-ai-cav">' + esc(x) + '</p>'; }) +
      '</details>' +
      '<p class="anl-ai-meta">Version ' + v.version + ' · ' + esc(v.period) + ' · Written by AI for ' + esc(v.by || 'a colleague') + ', ' +
        esc(CK.date(v.created_at) + ', ' + CK.clock(v.created_at, { space: true })) + '. Read before using.</p>';
  }
  function aiCard(page, cl) {
    var el = document.createElement('section');
    el.className = 'chartcard anl-ai';
    el.setAttribute('data-card', 'ai');
    el.innerHTML = '<div class="ovw-cardhead"><h3>AI analysis</h3><div class="anl-ai-acts"><span class="anl-ai-left" data-m="left"></span>' +
      '<button class="btn btn-sm" type="button" data-a="write">' + (AI ? AI.glyph : '') + '<span>Write with AI</span></button>' +
      '<span class="team-act" data-m="more" hidden><button class="kmenu-btn" type="button" data-a="menu" aria-label="More actions for the AI analysis" aria-expanded="false">' + DOTS + '</button>' +
      '<div class="kmenu" data-menu hidden role="menu">' +
        '<button class="kmenu-item" data-g="1" type="button" role="menuitem" data-a="versions">Versions</button>' +
        '<button class="kmenu-item" data-g="1" type="button" role="menuitem" data-a="download">Download</button>' +
        '<button class="kmenu-item is-danger" data-g="6" type="button" role="menuitem" data-a="delete">Delete</button></div></span></div></div>' +
      '<p class="msg" data-m="msg" role="status"></p><div class="anl-ai-body" data-m="body"></div>';
    page.appendChild(el);
    var body = el.querySelector('[data-m="body"]');
    var msg = function (t, tone) { var m = el.querySelector('[data-m="msg"]'); m.textContent = t || ''; m.className = 'msg' + (t ? ' ' + (tone || 'err') : ''); };
    var paint = function (list) {
      var v = shown && list.filter(function (x) { return x.id === shown; })[0] || list[0];
      shown = v ? v.id : null;
      el.querySelector('[data-m="more"]').hidden = !v;
      body.innerHTML = v ? readHtml(v) : '<p class="chart-empty">No analysis written.</p>';
    };
    var load = function () {
      UI.skeleton(body, 2);
      reads().then(paint).catch(function (e) { fail(body, 'AI analysis', e, load); });
      db.rpc('ai_analytics_left').then(function (r) {
        var d = r.data || {};
        el.querySelector('[data-m="left"]').textContent = r.error || d.error ? '' : d.left + ' left today';
      }).catch(function () {});
    };
    load();
    var menu = el.querySelector('[data-menu]'), mbtn = el.querySelector('[data-a="menu"]');
    var shut = function () { menu.hidden = true; mbtn.setAttribute('aria-expanded', 'false'); };
    el.addEventListener('click', function (e) {
      var b = e.target.closest && e.target.closest('[data-a]');
      if (!b) return;
      var k = b.getAttribute('data-a');
      if (k === 'menu') {
        e.stopPropagation();
        var open = menu.hidden;
        menu.hidden = !open; mbtn.setAttribute('aria-expanded', String(open));
        if (open && window.ADspaceMenu) { if (window.ADspaceMenu.tidy) window.ADspaceMenu.tidy(menu); window.ADspaceMenu.place(mbtn, menu); }
        return;
      }
      shut(); msg('');
      if (k === 'write') write(b, cl, el, msg, load);
      else reads().then(function (list) {
        var v = list.filter(function (x) { return x.id === shown; })[0];
        if (!v) return;
        if (k === 'versions') versions(list, function (id) { shown = id; paint(list); });
        if (k === 'download') download(v, msg);
        if (k === 'delete') remove(v, msg, load);
      });
    });
  }
  function write(btn, cl, el, msg, load) {
    if (!AI) return;
    /* Kept a colleague apart, so the demo's sample director never reads a
       real colleague's notes in this browser, and Sign out clears them. */
    var me = bridge.me && bridge.me();
    var key = 'adspace-analytics-notes:' + ((me && me.id) || 'anon'), was = '';
    try { was = localStorage.getItem(key) || ''; } catch (e) {}
    db.rpc('ai_analytics_left').then(function (r) {
      var d = r.data || {};
      if (r.error || d.error) { msg(aiSaid(r.error, d)); return; }
      if (!d.left) { msg(aiSaid(null, { error: 'ai-limit', limit: d.limit })); return; }
      window.ADspaceConfirm.ask({
        title: 'Write with AI',
        body: 'Reads the Sales and Clients figures for ' + spanWord(rangeOf(period)) + ' against the period before, never a client\'s name, and writes an analysis for management. ' +
          d.left + (d.left === 1 ? ' analysis' : ' analyses') + ' left today.',
        go: 'Write',
        fields: [{ name: 'notes', label: 'Notes for the analysis', rows: 3, required: false, placeholder: 'Optional', value: was }]
      }, function (v) {
        var notes = String(v.notes || '').trim();
        try { if (notes) localStorage.setItem(key, notes); else localStorage.removeItem(key); } catch (e) {}
        var label = btn.querySelector('span');
        btn.disabled = true; btn.setAttribute('aria-busy', 'true'); label.textContent = 'Writing';
        var period0 = PERIODS.filter(function (p) { return p[0] === period; })[0][1] + ' · ' + spanWord(rangeOf(period));
        db.functions.invoke('analytics-read', { body: { period: period0, figures: figuresOf(cl), notes: notes } }).then(function (res) {
          var out = res && res.data;
          btn.disabled = false; btn.removeAttribute('aria-busy'); label.textContent = 'Write with AI';
          if (res.error || !out || out.error || !out.read) { msg(aiSaid(res.error, out)); return; }
          delete memo.reads;
          shown = out.read.id;
          load();
          if (el.isConnected) msg('Analysis written.', 'ok');
        }).catch(function (e) {
          btn.disabled = false; btn.removeAttribute('aria-busy'); label.textContent = 'Write with AI';
          msg(aiSaid(e));
        });
      });
    }).catch(function (e) { msg(aiSaid(e)); });
  }
  function versions(list, pick) {
    window.ADspaceConfirm.ask({
      title: 'Versions', go: 'Show',
      fields: [{ name: 'v', label: 'Version', value: shown, choices: list.map(function (x) {
        return [x.id, 'Version ' + x.version + ' · ' + x.period + ' · ' + CK.date(x.created_at)];
      }) }]
    }, function (v) { pick(v.v); });
  }
  function remove(v, msg, load) {
    window.ADspaceConfirm.ask({ title: 'Delete this analysis?', body: 'Version ' + v.version + ' (' + v.period + ') is removed. This cannot be undone.',
      go: 'Delete', tone: 'danger', wait: true }, function () {
      return db.rpc('analytics_read_delete', { p_id: v.id }).then(function (r) {
        var d = r.data || {};
        if (r.error || d.error) return aiSaid(r.error, d);
        delete memo.reads; shown = null; load(); msg('Deleted.', 'ok');
        return '';
      }).catch(function (e) { return aiSaid(e); });
    });
  }
  /* The analysis as a PDF for management, drawn here and never stored; it
     asks the AI declaration first, as words written with AI that leave
     the portal. */
  function download(v, msg) {
    var docs = window.ADspaceDocs;
    if (!docs || !AI) return;
    AI.declare('analysis', 'Download', function () {
      var tab = docs.tabFor ? docs.tabFor() : null;
      drawPdf(v).then(function (blob) {
        return docs.save(blob, 'ADspace Analytics Analysis v' + v.version + '.pdf', tab);
      }).catch(function (e) { docs.shut(tab); msg((e && e.message) || 'The PDF could not be generated.'); });
    });
  }
  function drawPdf(v) {
    var docs = window.ADspaceDocs, a = v.analysis || {};
    return docs.lib().then(function (PDF) {
      var pdf;
      return PDF.PDFDocument.create().then(function (doc) {
        pdf = doc;
        pdf.setTitle('Analytics Analysis v' + v.version); pdf.setAuthor('ADSPACE PLT'); pdf.setCreator('ADspace Digital Portal'); pdf.setProducer('ADspace Digital Portal');
        return docs.embedFonts(pdf, PDF, { cjk: false });
      }).then(function (fonts) {
        var W = 595.28, H = 841.89, M = 48, FULL = W - 2 * M, FLOOR = 64;
        var ink = PDF.rgb(0.251, 0.251, 0.251), dark = PDF.rgb(0.106, 0.102, 0.090), mute = PDF.rgb(0.4, 0.4, 0.4);
        var book = fonts.font, reg = fonts.bold, med = fonts.med || fonts.bold, mark = fonts.mark || med;
        var safe = function (s) { s = String(s == null ? '' : s).replace(/→/g, '>'); return fonts.custom ? s : s.replace(/[^\x20-\x7E\xA0-\xFF]/g, '-'); };
        var page, y, pages = [];
        var text = function (s, x, yy, size, f, color) { page.drawText(safe(s), { x: x, y: yy, size: size, font: f || book, color: color || ink }); };
        var wrap = function (s, max, size, f) {
          var out = [], cur = '';
          safe(s).split(/(\s+)/).forEach(function (w) {
            if (!w) return;
            var t = cur + w;
            if ((f || book).widthOfTextAtSize(t, size) <= max || !cur.trim()) { cur = t; return; }
            out.push(cur.replace(/\s+$/, '')); cur = /^\s+$/.test(w) ? '' : w;
          });
          if (cur.trim()) out.push(cur.replace(/\s+$/, ''));
          return out;
        };
        var newPage = function () {
          page = pdf.addPage([W, H]); pages.push(page);
          text('ADspace', M, H - 52, 16, mark, ink);
          var fi = 'FOR INTERNAL USE';
          text(fi, (W - med.widthOfTextAtSize(fi, 7.5)) / 2, H - 50, 7.5, med, dark);
          y = H - 84;
        };
        var para = function (s, size, f, color, indent, gap) {
          var ls = wrap(s, FULL - (indent || 0), size, f), lh = size * 1.4;
          ls.forEach(function (l) { if (y - lh < FLOOR) newPage(); text(l, M + (indent || 0), y - size, size, f, color); y -= lh; });
          y -= gap == null ? 6 : gap;
        };
        var head = function (s) { if (y - 60 < FLOOR) newPage(); y -= 8; para(s, 12, med, dark, 0, 4); };
        newPage();
        para('Analytics Analysis', 20, reg, dark, 0, 4);
        para(v.period, 10, book, mute, 0, 2);
        para('Version ' + v.version + ' · Written with AI for ' + (v.by || 'a colleague') + ', ' + CK.date(v.created_at), 9, book, mute, 0, 14);
        para('Health: ' + (HEALTH[a.health] || HEALTH.mixed)[1], 11, med, dark, 0, 4);
        para(a.headline, 12, reg, dark, 0, 6);
        para(a.summary, 10.5, book, ink, 0, 8);
        if ((a.risks || []).length) { head('Risks'); a.risks.forEach(function (x, i) { para((i + 1) + '. ' + x.title + ' (' + (SEVERITY[x.severity] || SEVERITY.medium)[1] + ')', 10.5, med, dark, 0, 2); para(x.detail, 10, book, ink, 12, 6); }); }
        if ((a.working || []).length) { head('What Is Working'); a.working.forEach(function (x, i) { para((i + 1) + '. ' + x.title, 10.5, med, dark, 0, 2); para(x.detail, 10, book, ink, 12, 6); }); }
        if (a.forecast) { head('Forecast'); para(CREDIBLE[a.forecast.verdict] || '', 10.5, med, dark, 0, 2); if (a.forecast.detail) para(a.forecast.detail, 10, book, ink, 0, 6); }
        if ((a.actions || []).length) { head('Recommended Actions'); a.actions.forEach(function (x, i) { para((i + 1) + '. ' + x.action, 10.5, med, dark, 0, 2); para(x.why, 10, book, ink, 12, 6); }); }
        if ((a.caveats || []).length) { head('Caveats'); a.caveats.forEach(function (x) { para(x, 9.5, book, mute, 0, 4); }); }
        pages.forEach(function (p, i) {
          page = p;
          text('PRIVATE & CONFIDENTIAL', M, 34, 7.5, med, dark);
          var w = 'Page ' + (i + 1) + ' of ' + pages.length;
          text(w, W - M - book.widthOfTextAtSize(w, 7.5), 34, 7.5, book, mute);
        });
        return pdf.save();
      }).then(function (bytes) { return new Blob([bytes], { type: 'application/pdf' }); });
    });
  }

  // ---- The page --------------------------------------------------------------------------------------
  function bar(box) {
    var head = document.createElement('div');
    head.className = 'ovw-bar anl-bar';
    var tabs = TABS.filter(function (t) { return canTab(t[0]); });
    head.innerHTML = '<nav class="tabrow anl-tabs" id="anlTabs" role="tablist" aria-label="Analytics">' +
      tabs.map(function (t) {
        var on = t[0] === tab;
        return '<button class="tab' + (on ? ' is-on' : '') + '" type="button" role="tab" data-tab="' + t[0] + '" aria-selected="' + on + '"' +
          (on ? '' : ' tabindex="-1"') + '><span>' + esc(t[1]) + '</span></button>';
      }).join('') + '</nav>' +
      '<span class="ovw-when"><select class="select select-sm" id="anlPeriod" data-nofind aria-label="Period">' +
      PERIODS.map(function (p) { return '<option value="' + p[0] + '"' + (p[0] === period ? ' selected' : '') + '>' + p[1] + '</option>'; }).join('') +
      '</select><span class="ovw-span" id="anlSpan"></span></span>';
    box.appendChild(head);
    var strip = head.querySelector('#anlTabs');
    var sec = $('sectionAnalytics');
    if (sec) sec.setAttribute('data-swipe', 'anlTabs');
    if (window.ADspaceForm && window.ADspaceForm.thumb) window.ADspaceForm.thumb(strip);
    strip.addEventListener('click', function (e) {
      var t = e.target.closest && e.target.closest('.tab');
      if (t) go(t.getAttribute('data-tab'));
    });
    strip.addEventListener('keydown', function (e) {
      if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
      e.preventDefault();
      var ks = tabs.map(function (t) { return t[0]; }), i = ks.indexOf(tab);
      go(ks[(i + (e.key === 'ArrowRight' ? 1 : ks.length - 1)) % ks.length]);
      var on = $('anlTabs') && $('anlTabs').querySelector('.tab.is-on');
      if (on) on.focus();
    });
    head.querySelector('#anlSpan').textContent = spanWord(rangeOf(period)) + ' · As at ' + CK.clock(Date.now(), { space: true });
    var sel = head.querySelector('select');
    sel.addEventListener('change', function () {
      if (sel.value === period) return;
      period = sel.value;
      build(true);
      if (bridge.setUrl) bridge.setUrl();
      if ($('anlPeriod')) $('anlPeriod').focus({ preventScroll: true });
    });
  }
  function go(k) {
    if (k === tab || !canTab(k)) return;
    tab = k;
    build(false);
    if (bridge.setUrl) bridge.setUrl();
  }
  function build(keep) {
    var box = $('anlBody');
    if (!box) return;
    var y = keep ? window.scrollY : 0;
    box.innerHTML = '';
    bar(box);
    var page = document.createElement('div');
    page.className = 'anl-page';
    page.setAttribute('data-tab', tab);
    box.appendChild(page);
    var run = function () {
      UI.skeleton(page, 6);
      clients().then(function (cl) {
        page.innerHTML = '';
        if (ownOnly()) {
          var own = document.createElement('p');
          own.className = 'anl-own';
          own.textContent = 'Your clients only.';
          page.appendChild(own);
        }
        aiCard(page, cl);
        if (tab === 'sales') sales(page, cl); else clientsTab(page, cl);
      }).catch(function (e) { fail(page, tab === 'sales' ? 'Sales' : 'Clients', e, run); });
    };
    run();
    window.scrollTo(0, y);
  }
  function urlState() { return { tab: tab !== 'sales' ? tab : '', p: period !== '12' ? period : '' }; }
  function enter() {
    if (!$('anlBody')) return;
    if (!allowed()) { if (bridge.show) bridge.show('work'); return; }
    memo = {};
    var q = new URLSearchParams(location.search);
    var want = q.get('tab');
    var open = TABS.filter(function (t) { return canTab(t[0]); }).map(function (t) { return t[0]; });
    tab = open.indexOf(want) > -1 ? want : open[0];
    period = PERIODS.some(function (p) { return p[0] === q.get('p'); }) ? q.get('p') : '12';
    build(false);
    if (bridge.setUrl) bridge.setUrl();
  }

  window.ADspaceAnalytics = { enter: enter, urlState: urlState, allowed: allowed,
    _forecast: forecast, _season: seasonOf, _history: history, _range: rangeOf, _prev: prevOf, _monthsIn: monthsIn,
    _judge: judge, _churn: churnOf, _direction: direction };
  if (bridge.analyticsReady) bridge.analyticsReady();
})();
