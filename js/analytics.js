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
 * Everything is worked out on the page from the figures; nothing is written
 * by AI and nothing is stored.
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
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function may(key, lv) { return Boolean(bridge.may && bridge.may(key, lv || 'view')); }
  function pad2(n) { return String(n).padStart(2, '0'); }
  function plain(n) { return Number(n || 0).toLocaleString('en-GB'); }
  function one(n) { return (Math.round(n * 10) / 10).toLocaleString('en-GB', { maximumFractionDigits: 1 }); }
  function pct(n) { return Math.round(n * 100) + '%'; }
  function monthsWord(n) { return n === 1 ? '1 month' : n + ' months'; }
  function daysWord(n) { return n === 1 ? '1 day' : n + ' days'; }

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
      el.querySelector('.ovw-kpi-sub').textContent = t.sub || '';
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
    var churnRate = f.activeStart ? f.churned.length / f.activeStart : null;
    tiles(box, [
      { key: 'leads', label: 'New leads a month', fig: one(lead), sub: changeWord(lead, leadP, true),
        spark: keys.map(function (k) { return per(k, 'newLeads'); }) },
      { key: 'win', label: 'Win rate', fig: wr ? pct(wr.rate) : '—',
        sub: wr ? wr.won + ' of ' + wr.decided + ' leads decided' + (wrP ? ' · ' + pct(wrP.rate) + ' before' : '') : 'No lead decided in the period' },
      { key: 'toclient', label: 'Lead to client', fig: f.medianToWin == null ? '—' : daysWord(f.medianToWin),
        sub: 'Median' + (fp.medianToWin == null ? '' : ' · ' + daysWord(fp.medianToWin) + ' before') },
      { key: 'lost', label: 'Clients lost', fig: plain(f.churned.length),
        sub: (churnRate == null ? '' : 'Churn ' + pct(churnRate) + ' · ') + plain(fp.churned.length) + ' before',
        spark: keys.map(function (k) { return per(k, 'churned'); }) }
    ]);

    var g1 = row(box, true);
    trendCard(g1, h, keys, r);
    insights(g1, cl, f, fp, h);

    var g2 = row(box);
    season(g2, h);

    var g3 = row(box);
    var src = Object.keys(f.bySource).map(function (k) {
      var list = f.bySource[k], won = list.filter(everActive).length;
      return { label: k, value: list.length, won: won };
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
      if (full < 12) note = 'A forecast is drawn once 12 full months are held. ' + monthsWord(full) + (full === 1 ? ' is' : ' are') + ' held.';
    }
    var el = chart(grid, 'trend', 'Leads and new clients by month', {
      kind: 'line', cats: cats, series: series, band: band, bandWord: band ? 'Likely range' : '', none: 'No figure'
    }, aside, note);
    el.classList.add('anl-trend');
  }

  /* What changed: rules over the figures, the largest first, five at most. */
  function insights(grid, cl, f, fp, h) {
    var out = [];
    var a = f.newLeads.length, b = fp.newLeads.length;
    if (Math.max(a, b) >= 3 && b && Math.abs(a - b) / b >= .2) {
      out.push({ w: Math.abs(a - b) / b, dir: a > b ? 'up' : 'down', title: 'New leads',
        sub: a + ' in the period, against ' + b + ' in ' + prevWord(period), value: (a > b ? '+' : '−') + Math.round(Math.abs(a - b) / b * 100) + '%' });
    }
    var srcs = {};
    Object.keys(f.bySource).forEach(function (k) { srcs[k] = 1; });
    Object.keys(fp.bySource).forEach(function (k) { srcs[k] = 1; });
    Object.keys(srcs).forEach(function (k) {
      var x = (f.bySource[k] || []).length, y = (fp.bySource[k] || []).length;
      if (Math.max(x, y) < 3 || Math.abs(x - y) < 2) return;
      var ch = y ? (x - y) / y : 1;
      if (Math.abs(ch) < .5) return;
      out.push({ w: Math.abs(ch) * .9, dir: x > y ? 'up' : 'down', title: 'Leads from ' + k,
        sub: x + ' in the period, against ' + y + ' in ' + prevWord(period), value: y ? (x > y ? '+' : '−') + Math.round(Math.abs(ch) * 100) + '%' : 'New' });
    });
    var wr = winRate(f), wp = winRate(fp);
    if (wr && wp && wr.decided >= 3 && wp.decided >= 3 && Math.abs(wr.rate - wp.rate) >= .1) {
      out.push({ w: Math.abs(wr.rate - wp.rate) * 2, dir: wr.rate > wp.rate ? 'up' : 'down', title: 'Win rate',
        sub: wr.won + ' of ' + wr.decided + ' decided, against ' + wp.won + ' of ' + wp.decided, value: pct(wr.rate) });
    }
    if (f.medianToWin != null && fp.medianToWin != null && f.won.length >= 3 && fp.won.length >= 3 && fp.medianToWin &&
        Math.abs(f.medianToWin - fp.medianToWin) / fp.medianToWin >= .2) {
      out.push({ w: Math.abs(f.medianToWin - fp.medianToWin) / fp.medianToWin * .8, dir: f.medianToWin < fp.medianToWin ? 'down' : 'up',
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
    out.sort(function (x, y) { return y.w - x.w; });
    var ARROW = { up: '↑', down: '↓', '': '·' };
    var html = out.length ? '<div class="anl-ins">' + out.slice(0, 5).map(function (x) {
      return '<div class="anl-ins-row"><span class="anl-ins-dir" aria-hidden="true">' + ARROW[x.dir] + '</span>' +
        '<span class="anl-ins-what"><b>' + esc(x.title) + '</b><small>' + esc(x.sub) + '</small></span>' +
        '<span class="anl-ins-val">' + esc(x.value) + '</span></div>';
    }).join('') + '</div>' : '<div class="softpanel"><div class="emptyline"><b>No change large enough to show.</b></div></div>';
    card(grid, 'changed', 'What changed', 'On ' + prevWord(period), html).classList.add('anl-changed');
  }

  /* Each calendar month's average new leads, from 24 full months; until
     then, how many are held. */
  function season(grid, h) {
    var se = seasonOf(h, 'newLeads'), full = fullKeys(h).length;
    if (!se) {
      card(grid, 'season', 'Busiest months for new leads', '',
        waitHtml('Busiest months show once 24 full months of leads are held',
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
    tiles(box, [
      { key: 'active', label: 'Active clients', fig: plain(f.activeEnd), sub: plain(f.activeStart) + ' at the start of ' + monthLong(keys[0]),
        spark: keys.map(function (k) { return per(k, 'active'); }) },
      { key: 'joined', label: 'Clients joined', fig: plain(f.won.length), sub: plain(fp.won.length) + ' in ' + prevWord(period),
        spark: keys.map(function (k) { return per(k, 'won'); }) },
      { key: 'left', label: 'Clients left', fig: plain(f.churned.length), sub: plain(fp.churned.length) + ' in ' + prevWord(period),
        spark: keys.map(function (k) { return per(k, 'churned'); }) },
      { key: 'tenure', label: 'Time as a client', fig: med == null ? '—' : monthsWord(Math.round(med / 30.4)), sub: 'Median of active clients' }
    ]);
    var cur = CK.today().slice(0, 7);
    var g1 = row(box);
    chart(g1, 'active', 'Active clients by month', {
      kind: 'columns', labels: true,
      cats: keys.map(function (k) { return { label: monWord(k), long: monthLong(k), values: [per(k, 'active')], tone: k === cur ? 'mute' : '' }; }),
      series: [{ label: 'Active clients' }]
    }, spanWord(r));
    chart(g1, 'flow', 'Clients joined and left', {
      kind: 'line', cats: keys.map(function (k) { return { label: monWord(k), long: monthLong(k), values: [per(k, 'won'), per(k, 'churned')] }; }),
      series: [{ label: 'Joined' }, { label: 'Left', tone: 'mute' }]
    }, spanWord(r));
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
    _forecast: forecast, _season: seasonOf, _history: history, _range: rangeOf, _prev: prevOf, _monthsIn: monthsIn };
  if (bridge.analyticsReady) bridge.analyticsReady();
})();
