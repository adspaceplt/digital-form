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
 * or Paused without ever being Active; Churned is a client's first move out
 * of Active (Completed, a one-time project finished, is counted apart and
 * never churn); Paused counts moves into Paused; Resumed is Paused back to
 * Active; a Win-back is Past back to Active (eventsOf below).
 */
(function () {
  'use strict';
  var MON = window.ADspaceMoney;
  var LEADS = { lead: 1, contacted: 1, proposal: 1 };
  var REASONS = [['budget', 'Budget'], ['results', 'Results'], ['in_house', 'Moved in-house'],
                 ['closed', 'Business closed'], ['no_reply', 'No reply'], ['completed', 'Completed'],
                 ['other', 'Other']];
  /* A one-time project finished as agreed leaves for Past as Completed:
     never churn, which reads as a client lost (2026-11-15). */
  var DONE = 'completed';
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
  /* What a client's history counts, each once (the user, 2026-11-15): an
     Active client whose engagement ends goes to Paused for a holding period,
     then perhaps Past, and a lead that does not proceed goes to Paused while
     someone follows it up. So a client is counted once, at its first move out
     of Active (into Paused or Past): Churned, or Completed where that move,
     or the Paused to Past move after it, is a one-time project finished as
     agreed (`completed`); the later Paused to Past counts nothing again. A
     lead never Active is Lost once, at its first move into Paused or Past.
     Back to Active: a former Active client is Resumed (from Paused) or a
     Win-back (from Past); a lead's first Active is Won, Lost before or not. */
  var LEAVES = { churned: 1, completed: 1, lost: 1 };
  function eventsOf(c) {
    var out = [], everActive = false, leave = null, lostOnce = false;
    movesOf(c).forEach(function (m) {
      var into = m.to, was = m.from;
      if (into === 'active') {
        if (!everActive) out.push({ kind: 'won', at: m.at });
        else if (was === 'paused') out.push({ kind: 'resumed', at: m.at });
        else if (was === 'past') out.push({ kind: 'winback', at: m.at });
        everActive = true; leave = null;
        return;
      }
      if (into !== 'paused' && into !== 'past') return;
      if (everActive) {
        if (was === 'active' || (!leave && was !== 'paused' && was !== 'past')) {
          leave = { kind: m.reason === DONE ? 'completed' : 'churned', at: m.at };
          out.push(leave);
        } else if (leave && into === 'past' && m.reason === DONE) leave.kind = 'completed';
      } else if (!lostOnce) {
        lostOnce = true;
        out.push({ kind: 'lost', at: m.at });
      }
    });
    return out;
  }
  /* The client's last move inside a window: a leaving is counted only while
     that move leaves it out of Active (a move corrected back the same period
     counts nothing; 2026-10-20, the Dashboard audit). */
  function lastIn(mv, r) {
    var l = null;
    mv.forEach(function (m) { if (within(m.at, r)) l = m; });
    return l;
  }
  function counted(e, last) { return !last || last.to !== 'active' || new Date(last.at) < new Date(e.at); }
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
      newLeads: [], won: [], lost: [], churned: [], completed: [], paused: [], resumed: [], winback: [],
      pausedNow: [], activeNow: [], toWin: [], bySource: {}, byPerson: {}, bySales: {}, reasons: {}, months: [],
      /* When each client made the move it is counted for (the Dashboard's
         Clients who moved, 2026-11-12), by kind and client id. */
      at: { newLeads: {}, won: {}, lost: {}, churned: {}, completed: {}, paused: {}, resumed: {}, winback: {} }
    };
    /* A lead is sold, so its new leads, wins and losses go to the
       colleague it is Sales by (`sales_by`, an id); a client kept or lost
       after it is Active goes to its Person in charge (the user,
       2026-11-17: "the leads are only by sales by"). */
    var person = function (c, kind) {
      var sold = kind !== 'churned', k = sold ? (c.sales_by || '') : (c.owner || '');
      var map = sold ? f.bySales : f.byPerson;
      return map[k] || (map[k] = { key: k, name: sold ? '' : k, newLeads: [], won: [], lost: [], churned: [] });
    };
    clients.forEach(function (c) {
      var mv = movesOf(c), first = mv[0];
      if (LEADS[c.stage]) {
        f.pipeline[c.stage].push(c);
      }
      if (c.stage === 'paused') f.pausedNow.push(c);
      if (c.stage === 'active') f.activeNow.push(c);
      if (LEADS[first.to] && within(first.at, r)) {
        f.newLeads.push(c); person(c, 'newLeads').newLeads.push(c); f.at.newLeads[c.id] = first.at;
        var src = c.source || 'Not recorded';
        (f.bySource[src] = f.bySource[src] || []).push(c);
      }
      var everActive = false;
      mv.forEach(function (m) {
        var into = m.to, inside = within(m.at, r);
        if (into === 'active') everActive = true;
        if (into === 'paused' && inside) { f.paused.push(c); f.at.paused[c.id] = m.at; }
        if ((into === 'paused' || into === 'past') && inside && everActive) {
          var k = m.reason || '';
          var row = f.reasons[k] || (f.reasons[k] = { key: k, paused: [], past: [] });
          row[into].push(c);
        }
      });
      var seen = {}, ev = eventsOf(c), last = lastIn(mv, r);
      ev.forEach(function (e) {
        if (!within(e.at, r) || seen[e.kind]) return;
        if (e.kind === 'won') {
          f.toWin.push(Math.max(0, Math.round((new Date(e.at) - new Date(first.at)) / 86400000)));
        }
        if (LEAVES[e.kind] && !counted(e, last)) return;
        seen[e.kind] = true;
        f[e.kind].push(c); f.at[e.kind][c.id] = e.at;
        if (e.kind === 'won' || e.kind === 'lost' || e.kind === 'churned') person(c, e.kind)[e.kind].push(c);
      });
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
        churned: churnIn(clients, cur, end),
        completed: figures.count(clients, { from: cur, to: end }, 'completed')
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
      var last = lastIn(movesOf(c), r);
      if (eventsOf(c).some(function (e) { return e.kind === kind && within(e.at, r) && (!LEAVES[e.kind] || counted(e, last)); })) n++;
    });
    return n;
  };

  /* Committed monthly value: a month of each confirmed monthly line
     (quantity × the billed rate) that has started, by market, never added
     across currencies. A one-month line is a one-time item, never a month's
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
    return { active: sum(f.activeNow), won: sum(f.won), churned: sum(f.churned), byClient: byClient };
  }

  /* Better or worse (the Dashboard and Analytics read the one rule): a
     figure against the period before, `good` the way it should move ('up'
     or 'down'), Better or Worse once it moved by the Business setting
     `analytics_change_pct` (10%) and, for a count, by at least `min`;
     else Steady. Nothing to compare reads nothing. */
  function judge(now, before, good, min) {
    if (now == null || before == null || isNaN(now) || isNaN(before)) return null;
    var M = window.ADspaceMoney, raw = M && M.setting ? M.setting('analytics_change_pct') : null;
    var pct = raw == null || raw === '' || isNaN(Number(raw)) ? 10 : Number(raw);
    var d = now - before, thr = pct / 100;
    var rel = before ? Math.abs(d) / Math.abs(before) : (d ? 1 : 0);
    if (!d || rel < thr || (min && Math.abs(d) < min)) return { tone: 'off', word: 'Steady' };
    var ok = good === 'up' ? d > 0 : d < 0;
    return { tone: ok ? 'ok' : 'late', word: ok ? 'Better' : 'Worse' };
  }

  window.ADspaceSales = { figures: figures, reasonWord: reasonWord, movesOf: movesOf, judge: judge };
})();
