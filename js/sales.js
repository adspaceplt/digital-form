/*
 * Sales figures (`ADspaceSales`), the Dashboard's (2026-10-12: the Clients
 * Sales view it fed was removed, the user: "Priority is the dashboard"; its
 * figures moved there).
 *
 * A lead and a client are one record at different stages, so the figures are
 * read from what every client already carries: its stage history
 * (`stage_log`, each move dated and, into Paused or Past, with its reason),
 * its source and its person in charge. Nothing is typed for it and nothing is
 * stored by it.
 *
 * Words: Won is a lead's first move to Active; Lost is a lead moved to Past
 * without ever being Active; Churned is a client moved to Past; Paused is
 * at risk, counted on its own; Resumed is Paused back to Active; a Win-back
 * is Past back to Active.
 */
(function () {
  'use strict';
  var MON = window.ADspaceMoney;
  var LEADS = { lead: 1, contacted: 1, proposal: 1 };
  var REASONS = [['budget', 'Budget'], ['results', 'Results'], ['in_house', 'Moved in-house'],
                 ['closed', 'Business closed'], ['no_reply', 'No reply'], ['other', 'Other']];
  function reasonWord(k) {
    for (var i = 0; i < REASONS.length; i++) if (REASONS[i][0] === k) return REASONS[i][1];
    return k ? 'Other' : 'Not given';
  }
  /* Months are Malaysia's (js/clock.js), whatever the device's clock. */
  function monthWord(d) { return window.ADspaceClock.month(d); }
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
      pipeline: { lead: [], contacted: [], proposal: [] },
      newLeads: [], won: [], lost: [], churned: [], paused: [], resumed: [], winback: [],
      pausedNow: [], activeNow: [], toWin: [], bySource: {}, byPerson: {}, reasons: {}, months: []
    };
    var person = function (c) {
      var k = c.owner || 'No person in charge';
      return f.byPerson[k] || (f.byPerson[k] = { name: k, newLeads: [], won: [], lost: [], churned: [] });
    };
    clients.forEach(function (c) {
      var mv = movesOf(c), first = mv[0], everActive = false, lostIn = false, churnIn = false, lastIn = null;
      if (LEADS[c.stage]) {
        f.pipeline[c.stage].push(c);
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
        if (inside) lastIn = m;
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
        if (into === 'past' && inside) { if (everActive) churnIn = true; else lostIn = true; }
        if (into === 'paused' && inside) f.paused.push(c);
        if ((into === 'paused' || into === 'past') && inside && everActive) {
          var k = m.reason || '';
          var row = f.reasons[k] || (f.reasons[k] = { key: k, paused: [], past: [] });
          row[into].push(c);
        }
      });
      /* Lost or churned once a client in a period, and only while the
         period's last move leaves it in Past: a Past corrected back the same
         month counts nothing (2026-10-20, the Dashboard audit). */
      if (lastIn && lastIn.to === 'past') {
        if (churnIn) { f.churned.push(c); person(c).churned.push(c); }
        else if (lostIn) { f.lost.push(c); person(c).lost.push(c); }
      }
    });
    /* Active clients at each month's end inside the period (the last at
       now), and the net change over the period. */
    var CK = window.ADspaceClock, curKey = CK.day(r.from).slice(0, 7);
    var cur = CK.start(curKey + '-01');
    while (cur < r.to) {
      var end = CK.start(CK.addMonths(curKey, 1) + '-01');
      var at = Math.min(end.getTime(), r.to.getTime()) - 1;
      f.months.push({
        label: CK.MON[Number(curKey.slice(5, 7)) - 1], long: monthWord(curKey),
        active: clients.filter(function (c) { return stageAt(c, at) === 'active'; }).length,
        newLeads: f.newLeads.filter(function (c) { var t = new Date(movesOf(c)[0].at); return t >= cur && t < end; }).length,
        won: wonIn(clients, cur, end),
        churned: churnIn(clients, cur, end)
      });
      cur = end; curKey = CK.addMonths(curKey, 1);
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
      var everActive = false, churnIn = false, lastIn = null;
      movesOf(c).forEach(function (m) {
        var inside = within(m.at, r);
        if (inside) lastIn = m;
        if (m.to === 'active') {
          if (kind === 'won' && inside && !everActive && (m.from === null || LEADS[m.from])) n++;
          everActive = true;
        }
        if (m.to === 'past' && inside && everActive) churnIn = true;
      });
      if (kind === 'churned' && churnIn && lastIn && lastIn.to === 'past') n++;
    });
    return n;
  };

  /* Committed monthly value: a month of each confirmed monthly line
     (quantity × the billed rate) that has started, by market, never added
     across currencies. A one-month line is a one-off item, never a month's
     income, and a line starting later is not yet committed (2026-10-20, the
     Dashboard audit: RM 12,168.06 held a past creator list and a November
     start). A line with no term or start from before is counted. */
  function monthly(l, today) {
    if (l.state !== 'confirmed' || l.archived_at) return false;
    if (l.tenure != null && Number(l.tenure) <= 1) return false;
    return !l.start_on || String(l.start_on).slice(0, 10) <= today;
  }
  function money(clients, lines, f) {
    var byClient = {}, today = window.ADspaceClock.today();
    lines.forEach(function (l) {
      if (!monthly(l, today)) return;
      var v = Number(l.qty || 0) * (MON ? MON.rateFor(l.rate, l.tenure, l.term_adjust, l.term_pct) : Number(l.rate || 0));
      byClient[l.client_id] = (byClient[l.client_id] || 0) + v;
    });
    var sum = function (list) {
      var out = {};
      list.forEach(function (c) {
        var k = window.ADspaceMoney ? window.ADspaceMoney.curOf(c) : String(c.market || 'MY').toUpperCase();
        out[k] = (out[k] || 0) + (byClient[c.id] || 0);
      });
      return out;
    };
    return { active: sum(f.activeNow), won: sum(f.won), churned: sum(f.churned) };
  }

  window.ADspaceSales = { figures: figures, reasonWord: reasonWord, movesOf: movesOf };
})();
