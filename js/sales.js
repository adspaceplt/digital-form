/*
 * Sales — the Clients section's second view (`?s=clients&view=sales`).
 *
 * A lead and a client are one record at different stages, so the figures are
 * read from what every client already carries: its stage history
 * (`stage_log`, each move dated and, into Paused or Past, with its reason),
 * its source and its person in charge. Nothing is typed for it and nothing is
 * stored by it. A period choice sets every figure; every figure opens the
 * clients behind it. Committed monthly value, from confirmed service lines,
 * is an admin's alone (the user, 2026-10-04); the view is for admins and
 * Clients Full Access.
 *
 * Words: Won is a lead's first move to Active; Lost is a lead moved to Past
 * without ever being Active; Churned is a client moved to Past; Paused is
 * at risk, counted on its own; Resumed is Paused back to Active; a Win-back
 * is Past back to Active.
 */
(function () {
  'use strict';
  var API = window.ADspaceAPI;
  var db = API && API.client;
  var UI = window.ADspaceState;
  var CH = window.ADspaceChart;
  var GRP = window.ADspaceGroup;
  var MON = window.ADspaceMoney;
  var bridge = window.ADspaceAdmin || {};
  if (!API || !db || !UI || !CH || !GRP) return;
  var W = (window.ADspaceWords && window.ADspaceWords.en) || {};

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function may(k, lv) { return Boolean(bridge.may && bridge.may(k, lv || 'view')); }
  function isAdmin() {
    var m = bridge.me && bridge.me();
    return Boolean(m && (m.is_admin || m.role === 'admin'));
  }
  function allowed() { return isAdmin() || may('clients', 'manage'); }

  var MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
  var LEADS = { lead: 1, contacted: 1, proposal: 1 };
  var REASONS = [['budget', 'Budget'], ['results', 'Results'], ['in_house', 'Moved in-house'],
                 ['closed', 'Business closed'], ['no_reply', 'No reply'], ['other', 'Other']];
  var PERIODS = [['month', 'This month'], ['last', 'Last month'], ['3m', 'Last 3 months'],
                 ['6m', 'Last 6 months'], ['12m', 'Last 12 months']];
  var CLOSE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>';

  function stageWord(s) { return (W.stage && W.stage[s]) || s; }
  function reasonWord(k) {
    for (var i = 0; i < REASONS.length; i++) if (REASONS[i][0] === k) return REASONS[i][1];
    return k ? 'Other' : 'Not given';
  }
  function niceDate(d) {
    var x = new Date(d);
    return x.getDate() + ' ' + MONTHS[x.getMonth()] + ' ' + x.getFullYear();
  }
  function monthWord(d) { return MONTHS[d.getMonth()] + ' ' + d.getFullYear(); }
  function days(n) { return n === 1 ? '1 day' : n + ' days'; }
  function pct(a, b) { return b ? Math.round(a / b * 100) + '%' : '—'; }

  /* [from, to): a period ends where the next begins, and every period but
     Last month runs to now. */
  function range(key) {
    var now = new Date(), m0 = new Date(now.getFullYear(), now.getMonth(), 1);
    var back = function (n) { return new Date(m0.getFullYear(), m0.getMonth() - n, 1); };
    if (key === 'last') return { from: back(1), to: m0 };
    if (key === '3m') return { from: back(2), to: now };
    if (key === '6m') return { from: back(5), to: now };
    if (key === '12m') return { from: back(11), to: now };
    return { from: m0, to: now };
  }
  /* The period before, the same length and the same days: this month so far
     against the same days of last month, never against the whole of it. */
  function addMonths(d, n) {
    var x = new Date(d.getFullYear(), d.getMonth() + n, 1, d.getHours(), d.getMinutes(), d.getSeconds());
    var last = new Date(x.getFullYear(), x.getMonth() + 1, 0).getDate();
    x.setDate(Math.min(d.getDate(), last));
    return x;
  }
  var SPAN = { month: 1, last: 1, '3m': 3, '6m': 6, '12m': 12 };
  function prevRange(key) {
    var r = range(key), n = SPAN[key] || 1;
    return { from: addMonths(r.from, -n), to: addMonths(r.to, -n) };
  }
  /* A period in words without its year: a whole month is its name (Sept),
     whole months run month to month, anything else day to day. */
  function spanWord(r) {
    var a = r.from, b = new Date(r.to.getTime() - 1);
    var whole = a.getDate() === 1 && r.to.getDate() === 1 && r.to.getHours() === 0 && r.to.getMinutes() === 0;
    if (whole) return a.getMonth() === b.getMonth() ? MONTHS[a.getMonth()] : MONTHS[a.getMonth()] + ' to ' + MONTHS[b.getMonth()];
    if (a.getMonth() === b.getMonth()) return a.getDate() + ' to ' + b.getDate() + ' ' + MONTHS[a.getMonth()];
    return a.getDate() + ' ' + MONTHS[a.getMonth()] + ' to ' + b.getDate() + ' ' + MONTHS[b.getMonth()];
  }
  function delta(now, before, word) {
    var d = now - before;
    if (!d) return 'Same as ' + word;
    return (d > 0 ? '+' : '\u2212') + Math.abs(d) + ' on ' + word;
  }
  function within(at, r) { var t = new Date(at).getTime(); return t >= r.from.getTime() && t < r.to.getTime(); }

  /* A client's history as moves: the first entry is where it began. */
  function movesOf(c) {
    var log = (c.stage_log || []).filter(function (e) { return e && e.stage && e.at; });
    if (!log.length) log = [{ stage: c.stage || 'lead', at: c.stage_since || c.created_at }];
    return log.map(function (e, i) {
      return { from: i ? log[i - 1].stage : null, to: e.stage, at: e.at, reason: e.reason || '' };
    });
  }
  function stageAt(c, t) {
    var st = null;
    movesOf(c).forEach(function (m) { if (new Date(m.at).getTime() <= t) st = m.to; });
    return st;
  }

  /* Every figure, worked out from the clients and (for an admin) the
     confirmed lines. Exposed for the suite, which checks the arithmetic on
     histories of its own. */
  function figures(clients, lines, r) {
    var f = {
      pipeline: { lead: [], contacted: [], proposal: [], cold: [] },
      newLeads: [], won: [], lost: [], churned: [], paused: [], resumed: [], winback: [],
      pausedNow: [], activeNow: [], toWin: [], bySource: {}, byPerson: {}, reasons: {}, months: []
    };
    var STALE = (window.ADspaceCRM && window.ADspaceCRM.staleH) || { lead: 48, proposal: 21 * 24 };
    var now = Date.now();
    var person = function (c) {
      var k = c.owner || 'No person in charge';
      return f.byPerson[k] || (f.byPerson[k] = { name: k, newLeads: [], won: [], lost: [], churned: [] });
    };
    clients.forEach(function (c) {
      var mv = movesOf(c), first = mv[0], everActive = false;
      if (LEADS[c.stage]) {
        f.pipeline[c.stage].push(c);
        var since = new Date(c.stage_since || c.created_at).getTime();
        if (STALE[c.stage] && (now - since) / 3600000 > STALE[c.stage]) f.pipeline.cold.push(c);
      }
      if (c.stage === 'paused') f.pausedNow.push(c);
      if (c.stage === 'active') f.activeNow.push(c);
      if (LEADS[first.to] && within(first.at, r)) {
        f.newLeads.push(c); person(c).newLeads.push(c);
        var src = c.source || 'Not recorded';
        (f.bySource[src] = f.bySource[src] || []).push(c);
      }
      mv.forEach(function (m) {
        var into = m.to, was = m.from;
        var inside = within(m.at, r);
        if (into === 'active') {
          /* A client keyed in already Active is won the day it was keyed. */
          var firstWin = !everActive && (was === null || LEADS[was]);
          if (inside && firstWin) {
            f.won.push(c); person(c).won.push(c);
            f.toWin.push(Math.max(0, Math.round((new Date(m.at) - new Date(first.at)) / 86400000)));
          }
          if (inside && was === 'paused') f.resumed.push(c);
          if (inside && was === 'past') f.winback.push(c);
          everActive = true;
        }
        if (into === 'past' && inside) {
          if (!everActive) { f.lost.push(c); person(c).lost.push(c); }
          else { f.churned.push(c); person(c).churned.push(c); }
        }
        if (into === 'paused' && inside) f.paused.push(c);
        if ((into === 'paused' || into === 'past') && inside && everActive) {
          var k = m.reason || '';
          var row = f.reasons[k] || (f.reasons[k] = { key: k, paused: [], past: [] });
          row[into].push(c);
        }
      });
    });
    /* Active clients at each month's end inside the period (the last at
       now), and the net change over the period. */
    var cur = new Date(r.from.getFullYear(), r.from.getMonth(), 1);
    while (cur < r.to) {
      var end = new Date(cur.getFullYear(), cur.getMonth() + 1, 1);
      var at = Math.min(end.getTime(), r.to.getTime()) - 1;
      f.months.push({
        label: MONTHS[cur.getMonth()], long: monthWord(cur),
        active: clients.filter(function (c) { return stageAt(c, at) === 'active'; }).length,
        newLeads: f.newLeads.filter(function (c) { var t = new Date(movesOf(c)[0].at); return t >= cur && t < end; }).length,
        won: wonIn(clients, cur, end),
        churned: churnIn(clients, cur, end)
      });
      cur = end;
    }
    var startT = r.from.getTime() - 1;
    f.activeStart = clients.filter(function (c) { return stageAt(c, startT) === 'active'; }).length;
    f.activeEndList = clients.filter(function (c) { return stageAt(c, r.to.getTime() - 1) === 'active'; });
    f.activeEnd = f.activeEndList.length;
    /* The period's leads, step by step: how far each has got (a client
       once Active counts as Active whatever it is now). */
    var RANK = { lead: 0, contacted: 1, proposal: 2, active: 3, paused: 3 };
    f.funnel = [0, 1, 2, 3].map(function (k) {
      return f.newLeads.filter(function (c) {
        return movesOf(c).some(function (m) { return RANK[m.to] != null && RANK[m.to] >= k; });
      });
    });
    /* Who needs a call: leads over their time in stage and paused clients,
       the longest waiting first. */
    var waited = function (c) { return Math.max(0, Math.floor((now - new Date(c.stage_since || c.created_at).getTime()) / 86400000)); };
    f.attention = f.pipeline.cold.map(function (c) { return { c: c, days: waited(c), kind: 'cold' }; })
      .concat(f.pausedNow.map(function (c) { return { c: c, days: waited(c), kind: 'paused' }; }))
      .sort(function (a, b) { return b.days - a.days || String(a.c.name).localeCompare(String(b.c.name)); });
    f.toWin.sort(function (a, b) { return a - b; });
    f.medianToWin = f.toWin.length ? f.toWin[Math.floor((f.toWin.length - 1) / 2)] : null;
    f.money = lines ? money(clients, lines, f) : null;
    return f;
  }
  function wonIn(clients, from, to) {
    return figures.count(clients, { from: from, to: to }, 'won');
  }
  function churnIn(clients, from, to) {
    return figures.count(clients, { from: from, to: to }, 'churned');
  }
  /* One kind of move counted over a window, the same rules as above. */
  figures.count = function (clients, r, kind) {
    var n = 0;
    clients.forEach(function (c) {
      var everActive = false;
      movesOf(c).forEach(function (m) {
        var inside = within(m.at, r);
        if (m.to === 'active') {
          if (kind === 'won' && inside && !everActive && (m.from === null || LEADS[m.from])) n++;
          everActive = true;
        }
        if (m.to === 'past' && inside && everActive && kind === 'churned') n++;
      });
    });
    return n;
  };

  /* Committed monthly value: a month of each confirmed line (quantity × the
     billed rate), by market, never added across currencies. */
  function money(clients, lines, f) {
    var byClient = {};
    lines.forEach(function (l) {
      if (l.state !== 'confirmed' || l.archived_at) return;
      var v = Number(l.qty || 0) * (MON ? MON.rateFor(l.rate, l.tenure, l.term_adjust, l.term_pct) : Number(l.rate || 0));
      byClient[l.client_id] = (byClient[l.client_id] || 0) + v;
    });
    var sum = function (list) {
      var out = {};
      list.forEach(function (c) {
        var k = String(c.market || 'MY').toUpperCase();
        out[k] = (out[k] || 0) + (byClient[c.id] || 0);
      });
      return out;
    };
    return { active: sum(f.activeNow), won: sum(f.won), churned: sum(f.churned) };
  }
  function moneyWord(by) {
    var keys = Object.keys(by).filter(function (k) { return by[k]; });
    if (!keys.length) return MON ? MON.money(0, 'MY', 2) : '0';
    return keys.sort().map(function (k) { return MON ? MON.money2(by[k], k) : by[k].toFixed(2); }).join(' · ');
  }

  // ---- Drawing --------------------------------------------------------------
  var st = { host: null, period: 'month', clients: null, lines: null, linesErr: null, err: null, onOpen: null, seq: 0 };

  function heading(host, text) {
    var h = document.createElement('h3');
    h.className = 'ovsec-title';
    h.textContent = text;
    host.appendChild(h);
  }
  /* A figure that opens the clients behind it: a `.linkbtn` holding the
     count, or the bare count where there is nobody to open. */
  function drill(list, label) {
    var n = list.length;
    if (!n) return '<span class="sl-n">0</span>';
    return '<button class="linkbtn sl-drill" type="button" aria-haspopup="dialog" aria-expanded="false" data-drill="' +
      esc(label) + '">' + n + '</button>';
  }
  function table(host, title, heads, rows, note) {
    heading(host, title);
    if (!rows.length) {
      var sub = document.createElement('div');
      sub.className = 'repempty';
      host.appendChild(sub);
      UI.emptyLine(sub, note || 'Nothing in this period.');
      return;
    }
    var t = GRP.table('svc-row rep-row sl-row', heads);
    rows.forEach(function (r) {
      var row = document.createElement('div');
      row.className = 'svc-row rep-row sl-row';
      row.innerHTML = r.html;
      (r.lists || []).forEach(function (pair) {
        var b = row.querySelector('[data-drill="' + pair[0] + '"]');
        if (b) b.addEventListener('click', function (e) { e.stopPropagation(); openList(b, pair[1], pair[2]); });
      });
      t.appendChild(row);
    });
    host.appendChild(t);
  }
  /* A row: the measure and a mute line, a middle cell named for a phone, the
     figure at the right edge. */
  function line(name, note, midLabel, mid, figure) {
    return '<span class="svc-name"><b>' + esc(name) + '</b>' + (note ? '<small>' + esc(note) + '</small>' : '') + '</span>' +
      '<span class="rep-mid">' + (midLabel ? '<span class="rep-lab">' + esc(midLabel) + ' </span>' : '') + mid + '</span>' +
      '<span class="rep-num">' + figure + '</span>';
  }

  function cell(grid) {
    var c = document.createElement('div');
    c.className = 'sl-cell';
    grid.appendChild(c);
    return c;
  }
  /* A headline figure: the number, its name and the change on the period
     before, the whole cell opening the clients behind it. */
  function headCell(label, list, value, note, id) {
    var inner = '<b>' + esc(value) + '</b><span>' + esc(label) + '</span>' + (note ? '<small>' + esc(note) + '</small>' : '');
    if (!list || !list.length) return '<div class="tally-cell sl-head">' + inner + '</div>';
    return '<button class="tally-cell sl-head" type="button" aria-haspopup="dialog" aria-expanded="false" data-head="' + id + '">' + inner + '</button>';
  }

  // ---- The clients behind a figure -----------------------------------------
  var pop = null, popBtn = null;
  function shutPop(back) {
    if (!pop || pop.hidden) return;
    pop.hidden = true;
    if (popBtn) { popBtn.setAttribute('aria-expanded', 'false'); if (back) popBtn.focus(); }
  }
  function openList(btn, title, list) {
    if (pop && !pop.hidden && popBtn === btn) { shutPop(); return; }
    if (!pop) {
      pop = document.createElement('div');
      pop.className = 'kmenu sl-pop'; pop.id = 'salesPop'; pop.hidden = true; pop.tabIndex = -1;
      pop.setAttribute('role', 'dialog'); pop.setAttribute('aria-labelledby', 'salesPopTitle');
      document.body.appendChild(pop);
      pop.addEventListener('click', function (e) { e.stopPropagation(); });
      document.addEventListener('click', function () { shutPop(); });
      window.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && pop && !pop.hidden) { e.stopImmediatePropagation(); e.preventDefault(); shutPop(true); }
      }, true);
      if (window.ADspaceMenu) window.ADspaceMenu.onScroll(function () { shutPop(); });
    }
    if (popBtn && popBtn !== btn) popBtn.setAttribute('aria-expanded', 'false');
    popBtn = btn;
    var seen = {};
    var uniq = list.filter(function (c) { if (seen[c.id]) return false; seen[c.id] = 1; return true; })
      .sort(function (a, b) { return String(a.name).localeCompare(String(b.name)); });
    pop.innerHTML = '<div class="popcard-head"><p class="sl-pop-title" id="salesPopTitle">' + esc(title) + '</p>' +
      '<button class="iconbtn popcard-x" type="button" data-a="x" aria-label="Close">' + CLOSE + '</button></div>' +
      '<ul class="sl-poplist">' + uniq.map(function (c) {
        return '<li><button class="kmenu-item" type="button" data-id="' + esc(c.id) + '"><b>' + esc(c.name) + '</b>' +
          '<span>' + esc(stageWord(c.stage)) + '</span></button></li>';
      }).join('') + '</ul>';
    Array.prototype.forEach.call(pop.querySelectorAll('[data-id]'), function (b) {
      b.addEventListener('click', function () {
        var c = uniq.filter(function (x) { return x.id === b.getAttribute('data-id'); })[0];
        shutPop();
        if (c && st.onOpen) st.onOpen(c);
      });
    });
    pop.querySelector('[data-a="x"]').onclick = function () { shutPop(true); };
    pop.hidden = false;
    btn.setAttribute('aria-expanded', 'true');
    if (window.ADspaceMenu) window.ADspaceMenu.pop(btn, pop, 'right');
    try { pop.focus({ preventScroll: true }); } catch (e) { pop.focus(); }
  }

  function paint() {
    var host = st.host;
    if (!host) return;
    if (st.err) { UI.failLine(host, 'Sales figures', st.err, function () { load(true); }); return; }
    if (!st.clients) { UI.skeleton(host, 5); return; }
    var r = range(st.period);
    var f = figures(st.clients, st.lines, r);
    host.innerHTML = '';
    var win = document.createElement('p');
    win.className = 'routenote repwin';
    win.textContent = 'Reporting period: ' + niceDate(r.from) + ' to ' + niceDate(new Date(r.to.getTime() - 1));
    host.appendChild(win);

    var p = figures(st.clients, null, prevRange(st.period));
    var was = { '3m': 'the 3 months before', '6m': 'the 6 months before', '12m': 'the year before' }[st.period] ||
      spanWord(prevRange(st.period));

    /* 1. The headline: what came in, what was won, what was lost, where the
          book stands, and (an admin's) what it is worth a month. */
    var heads = document.createElement('div');
    heads.className = 'tally sl-heads';
    var cells = [
      headCell('New leads', f.newLeads, f.newLeads.length, delta(f.newLeads.length, p.newLeads.length, was), 'new'),
      headCell('Won', f.won, f.won.length, delta(f.won.length, p.won.length, was), 'won'),
      headCell('Churned', f.churned, f.churned.length, delta(f.churned.length, p.churned.length, was), 'churned'),
      headCell('Active clients', f.activeEndList, f.activeEnd, delta(f.activeEnd, f.activeStart, was), 'active')
    ];
    if (f.money) cells.push('<div class="tally-cell sl-head is-total"><b>' + esc(moneyWord(f.money.active)) +
      '</b><span>Committed monthly value</span><small>Confirmed lines</small></div>');
    heads.innerHTML = cells.join('');
    var LISTS = { new: ['New leads', f.newLeads], won: ['Won', f.won], churned: ['Churned', f.churned], active: ['Active clients', f.activeEndList] };
    Array.prototype.forEach.call(heads.querySelectorAll('[data-head]'), function (b) {
      var l = LISTS[b.getAttribute('data-head')];
      b.addEventListener('click', function (e) { e.stopPropagation(); openList(b, l[0], l[1]); });
    });
    host.appendChild(heads);

    /* 2. The period's leads step by step, beside who needs a call today. */
    var split = document.createElement('div');
    split.className = 'sl-split';
    host.appendChild(split);
    var F = f.funnel, n0 = F[0].length;
    var stepNote = function (k) { return k && F[k - 1].length ? pct(F[k].length, F[k - 1].length) + ' of the step before' : ''; };
    CH.draw(split, { kind: 'bars', title: 'This period\'s leads', empty: 'No new leads in this period.',
      rows: n0 ? [
        { label: 'New leads', value: F[0].length },
        { label: 'Contacted', value: F[1].length, note: stepNote(1) },
        { label: 'Proposal sent', value: F[2].length, note: stepNote(2) },
        { label: 'Became clients', value: F[3].length, note: stepNote(3), tone: 'ok' }
      ] : [] });
    var att = document.createElement('article');
    att.className = 'chartcard ovw-card sl-attention';
    att.innerHTML = '<div class="ovw-cardhead"><h3>Needs attention</h3>' +
      (f.attention.length ? '<span class="ovw-count tone is-warn">' + f.attention.length + '</span>' : '') + '</div><div class="ovw-body"></div>';
    split.appendChild(att);
    var ab = att.querySelector('.ovw-body');
    if (!f.attention.length) UI.emptyLine(ab, 'Nothing waiting.');
    else {
      var SHOW = 6;
      ab.innerHTML = '<div class="ovw-rows">' + f.attention.slice(0, SHOW).map(function (a, k) {
        var meta = a.kind === 'paused'
          ? 'Paused' + (a.c.stage_reason ? ' · ' + reasonWord(a.c.stage_reason) : '')
          : stageWord(a.c.stage) + ' · Going cold';
        return '<button class="ovw-row" type="button" data-k="' + k + '"><span class="ovw-who"><b>' + esc(a.c.name) + '</b>' +
          '<small>' + esc(meta) + '</small></span><span class="ovw-fig"><b' + (a.kind === 'cold' ? ' class="is-warn"' : '') + '>' +
          esc(days(a.days)) + '</b>' + (a.c.owner ? '<small>' + esc(a.c.owner) + '</small>' : '') + '</span></button>';
      }).join('') + '</div>' + (f.attention.length > SHOW ? '<p class="ovw-more">' + (f.attention.length - SHOW) + ' more</p>' : '');
      Array.prototype.forEach.call(ab.querySelectorAll('.ovw-row'), function (b) {
        var a = f.attention[Number(b.getAttribute('data-k'))];
        b.addEventListener('click', function () { if (st.onOpen) st.onOpen(a.c); });
      });
    }

    /* 3. Over the period's months, side by side. */
    if (f.months.length > 1) {
      var trend = document.createElement('div');
      trend.className = 'chartgrid sl-trend';
      host.appendChild(trend);
      CH.draw(trend, { kind: 'line', title: 'Active clients by month', none: 'No figure',
        cats: f.months.map(function (m) { return { label: m.label, long: m.long, values: [m.active] }; }),
        series: [{ label: 'Active clients', tone: '' }] });
      CH.draw(trend, { kind: 'columns', title: 'Leads, won and churned by month',
        cats: f.months.map(function (m) { return { label: m.label, long: m.long, values: [m.newLeads, m.won, m.churned] }; }),
        series: [{ label: 'New leads', tone: 'mute' }, { label: 'Won', tone: 'ok' }, { label: 'Churned', tone: 'warn' }] });
    }

    /* 4. The breakdowns, two across at a desk. */
    var grid = document.createElement('div');
    grid.className = 'sl-grid';
    host.appendChild(grid);
    var P = f.pipeline;
    table(cell(grid), 'Pipeline now', ['Stage', '', 'Clients'], [
      { html: line('Lead', '', '', '', drill(P.lead, 'pl-lead')), lists: [['pl-lead', 'Lead', P.lead]] },
      { html: line('Contacted', '', '', '', drill(P.contacted, 'pl-con')), lists: [['pl-con', 'Contacted', P.contacted]] },
      { html: line('Proposal sent', '', '', '', drill(P.proposal, 'pl-pro')), lists: [['pl-pro', 'Proposal sent', P.proposal]] }
    ]);
    var decided = f.won.length + f.lost.length;
    table(cell(grid), 'Other moves', ['Move', '', 'Figure'], [
      { html: line('Lost leads', 'Past before ever Active', '', '', drill(f.lost, 'p-lost')), lists: [['p-lost', 'Lost leads', f.lost]] },
      { html: line('Paused', f.pausedNow.length + ' paused now', '', '', drill(f.paused, 'p-pau')), lists: [['p-pau', 'Paused', f.paused]] },
      { html: line('Resumed', 'Paused back to Active', '', '', drill(f.resumed, 'p-res')), lists: [['p-res', 'Resumed', f.resumed]] },
      { html: line('Win-backs', 'Past back to Active', '', '', drill(f.winback, 'p-wb')), lists: [['p-wb', 'Win-backs', f.winback]] },
      { html: line('Lead to won', 'Median', '', '', esc(f.medianToWin === null ? '\u2014' : days(f.medianToWin))) },
      { html: line('Conversion', 'Won of the leads decided', '', '', esc(pct(f.won.length, decided))) },
      { html: line('Churn rate', 'Churned of those active at the start', '', '', esc(pct(f.churned.length, f.activeStart))) }
    ]);
    var src = Object.keys(f.bySource).sort(function (a, b) { return f.bySource[b].length - f.bySource[a].length || a.localeCompare(b); });
    table(cell(grid), 'New leads by source', ['Source', '', 'Leads'], src.map(function (k, i) {
      return { html: line(k, '', '', '', drill(f.bySource[k], 'src-' + i)), lists: [['src-' + i, k, f.bySource[k]]] };
    }), 'No new leads in this period.');
    var rk = REASONS.map(function (x) { return x[0]; }).concat(['']).filter(function (k) { return f.reasons[k]; });
    table(cell(grid), 'Why clients paused or left', ['Reason', 'Paused', 'Past'], rk.map(function (k, i) {
      var row = f.reasons[k];
      return { html: line(reasonWord(k), '', 'Paused', drill(row.paused, 'rs-p' + i), drill(row.past, 'rs-x' + i)),
        lists: [['rs-p' + i, reasonWord(k) + ' · Paused', row.paused], ['rs-x' + i, reasonWord(k) + ' · Past', row.past]] };
    }), 'No client paused or left in this period.');
    var ppl = Object.keys(f.byPerson).sort(function (a, b) { return a.localeCompare(b); }).map(function (k) { return f.byPerson[k]; })
      .filter(function (q) { return q.newLeads.length || q.won.length || q.lost.length || q.churned.length; });
    table(cell(grid), 'By person in charge', ['Person in charge', 'Won and lost', 'Churned'], ppl.map(function (q, i) {
      return { html: line(q.name, q.newLeads.length + (q.newLeads.length === 1 ? ' new lead' : ' new leads'), '',
          '<span class="rep-lab">Won </span>' + drill(q.won, 'pw' + i) + '<span class="rep-lab"> · Lost </span>' + drill(q.lost, 'pl' + i),
          drill(q.churned, 'pc' + i)),
        lists: [['pw' + i, q.name + ' · Won', q.won], ['pl' + i, q.name + ' · Lost', q.lost], ['pc' + i, q.name + ' · Churned', q.churned]] };
    }), 'Nothing in this period.');

    /* Money, an admin's alone. A refused read of the lines is said, never
       drawn as nothing committed. */
    if (st.linesErr) {
      var mc = cell(grid);
      heading(mc, 'Committed monthly value');
      var fail = document.createElement('div');
      fail.className = 'repempty';
      mc.appendChild(fail);
      UI.failLine(fail, 'Service lines', st.linesErr, function () { load(true); });
    } else if (f.money) {
      table(cell(grid), 'Monthly value moved', ['Measure', '', 'A month'], [
        { html: line('Won in this period', '', '', '', esc(moneyWord(f.money.won))) },
        { html: line('Lost to churn in this period', '', '', '', esc(moneyWord(f.money.churned))) }
      ]);
    }
  }

  function load(force) {
    if (st.clients && !force) { paint(); return; }
    var seq = ++st.seq;
    st.err = null;
    if (st.host) UI.skeleton(st.host, 5);
    var reads = [db.from('clients').select('id, name, slug, stage, stage_reason, stage_log, stage_since, created_at, source, owner, market')];
    if (isAdmin()) reads.push(db.from('client_services').select('client_id, qty, rate, tenure, term_adjust, term_pct, state, archived_at'));
    Promise.all(reads).then(function (r) {
      if (seq !== st.seq) return;
      if (r[0].error) throw r[0].error;
      st.clients = r[0].data || [];
      st.lines = r[1] && !r[1].error ? (r[1].data || []) : null;
      st.linesErr = r[1] && r[1].error ? (r[1].error.message || 'refused') : null;
      paint();
    }).catch(function (e) {
      if (seq !== st.seq) return;
      st.err = (e && e.message) || String(e);
      paint();
    });
  }

  window.ADspaceSales = {
    allowed: allowed,
    PERIODS: PERIODS,
    /* Draws into `host` for `period`, reading once a visit; `onOpen(client)`
       opens a client from the list behind a figure. */
    show: function (host, period, onOpen, fresh) {
      st.host = host;
      st.period = period || 'month';
      st.onOpen = onOpen;
      load(Boolean(fresh));
    },
    period: function (p) { st.period = p || 'month'; paint(); },
    figures: figures,
    range: range,
    prev: prevRange
  };
})();
