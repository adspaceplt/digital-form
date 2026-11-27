/*
 * Money, for a portal that bills in two countries.
 *
 * Every figure used to be printed with "RM" in front of it, which was wrong
 * the moment a Singapore client opened their page. Currency follows the
 * client's billing choice: a Singapore client is billed in RM unless its
 * Billing sets S$ (`bill_sgd`, 2026-10-22), and `curOf(client)` is the one
 * reading of it.
 *
 * Tax is a separate question with a separate answer. ADspace is a Malaysian
 * entity, so the tax is Malaysian service tax at 8% whoever is being billed:
 * a Singapore client is invoiced in S$ and still carries SST. Currency follows
 * the client; the tax follows us. The only per-client switch is whether it
 * applies at all, for a client who is genuinely exempt.
 */
(function () {
  // Currency only. The tax below is ours, not the market's.
  var MARKETS = {
    MY: { code: 'MYR', sign: 'RM', locale: 'en-MY' },
    SG: { code: 'SGD', sign: 'S$', locale: 'en-SG' }
  };

  /* THE FIGURES ARE SETTINGS (2026-10-05). SST and the term percentages are
     an admin's to change from a day on (`app_settings`, read through
     `app_settings_read()`), each kept with the day it took effect, so a
     letter redrawn later is priced by the figures of its own day. `load()`
     reads them once per page; `FIRST` is what each held before the setting
     existed (the migration's seed), used only where the read fails.
     `term_18_23` has no seed: unset, 18 months takes 12's, as
     `quote_term_pct` does (2026-11-24). */
  var FIRST = { sst_pct: 8, term_1_3: 25, term_4_5: 15, term_6_11: 0, term_12_23: -5, term_24: -10,
    lead_followup_hours: 48, proposal_followup_days: 21, report_due_days: 7, revision_due_days: 1,
    ai_price_in: 4, ai_price_out: 20, reach_allowance_pct: 0.5, approval_reminder_days: 3, ai_price_search: 10, ai_price_image: 0.07,
    priority_urgent_hours: 24, priority_high_hours: 48, priority_medium_hours: 72, task_remind_hours: 3, task_start_days: 2, task_past_days: 30, stage_back_days: 7, quote_valid_days: 30, quote_reply_days: 2, details_form_days: 14, wa_repeat_hours: 24, quote_wa_day: 30,
    vic_lead_followup_hours: 24, vic_proposal_followup_days: 7, abroad_days: 14, abroad_remind_hours: 2, session_idle_days: 30, hiring_invite_days: 3, hiring_reply_days: 3, hiring_decision_days: 7, hiring_link_days: 30, hiring_pool_months: 12, hiring_keep_months: 12, health_cap_default: 45, health_near_pct: 90, health_task_hours: 2, health_remind_days: 2, health_alert: 1,
    /* A creator's payment, working days after the post (2026-11-09). */
    creator_pay_days_myr: 10, creator_pay_days_other: 21,
    /* Client feedback: months since a client was last asked (2026-11-24). */
    feedback_quiet_months: 6,
    /* The month Analytics counts its history from, YYYYMM (2026-10-25). */
    analytics_from: 202609,
    /* When an Analytics figure reads better or worse, and when churn is an
       alert (2026-10-25). */
    analytics_change_pct: 10, analytics_churn_pct: 10,
    /* Working hours (2026-11-20): Monday to Friday 10:00am to 7:00pm, a
       one-hour lunch, Saturday and Sunday on demand (1). */
    work_start: 1000, work_end: 1900, work_lunch_min: 60, work_weekend: 1,
    /* How ad spend works (2026-11-27): the next month's prepaid budget
       requested at about 80% spent; the Agency Credit Term Fee, 20%. */
    ad_prepay_pct: 80, ad_credit_fee_pct: 20 };
  var ROWS = [];
  var loading = null;
  function today() {
    try { return new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Kuala_Lumpur' }); }
    catch (e) { return new Date().toISOString().slice(0, 10); }
  }
  /* A day is read in Malaysia: a timestamp (an issued letter's) becomes its
     MYT date, so a change from a day applies from that day's midnight here. */
  function dayOf(at) {
    if (!at) return today();
    var s = String(at);
    if (s.length <= 10) return s;
    try { return new Date(s).toLocaleDateString('en-CA', { timeZone: 'Asia/Kuala_Lumpur' }); }
    catch (e) { return s.slice(0, 10); }
  }
  function setting(key, at) {
    var day = dayOf(at);
    var rows = ROWS.filter(function (r) { return r.key === key; })
      .sort(function (a, b) { return a.from < b.from ? -1 : 1; });
    var on = rows.filter(function (r) { return r.from <= day; });
    /* No row in force on the day: the seed's figure, else unset (a figure
       planned for a later day is not read before it; 2026-10-22, BE-5). */
    var r = on[on.length - 1];
    return r ? Number(r.value) : FIRST[key];
  }
  /* The next change of a figure set from a later day, if any:
     `{ from, value }` (the Settings page says it; 2026-10-14). */
  function next(key) {
    var day = today();
    var r = ROWS.filter(function (x) { return x.key === key && x.from > day; })
      .sort(function (a, b) { return a.from < b.from ? -1 : 1; })[0];
    return r ? { from: r.from, value: Number(r.value) } : null;
  }
  /* The figures are kept for a few minutes, never the page's life
     (2026-11-26, F4: Build quote's S$ read 3.15 after Settings held 3.18):
     a load() after STALE asks again, the page coming back into view or
     focus asks again after ONVIEW, a new Malaysian day re-reads them, and
     a save in another tab (its load(true)) tells this one through
     localStorage (`adspace-settings-at`). Nothing is asked on a timer. */
  var STALE = 5 * 60 * 1000, ONVIEW = 60 * 1000, askedAt = 0, readDay = '';
  function fresh(within) { return Date.now() - askedAt < within && readDay === today(); }
  function read() {
    var api = window.ADspaceAPI, db = api && api.client;
    if (!db) return (loading = Promise.resolve(null));
    askedAt = Date.now(); readDay = today();
    /* A failed read is not kept: the next load() asks again (2026-10-19). */
    var p = loading = db.rpc('app_settings_read').then(function (r) {
      if (r.error || !r.data) { if (loading === p) loading = null; return null; }
      ROWS = (r.data.settings || []).map(function (x) { return { key: x.key, from: String(x.from).slice(0, 10), value: x.value, by: x.by, at: x.at }; });
      TAX.rate = setting('sst_pct') / 100; TAX.label = taxLabel();
      /* Read afresh: what follows a switch (a send drawn off) repaints. */
      try { document.dispatchEvent(new CustomEvent('adspace-settings')); } catch (e) { /* an old browser */ }
      return r.data;
    }).catch(function () { if (loading === p) loading = null; return null; });
    return p;
  }
  function load(force) {
    if (loading && !force && fresh(STALE)) return loading;
    var p = read();
    if (force) { try { localStorage.setItem('adspace-settings-at', String(Date.now())); } catch (e) { /* storage off */ } }
    return p;
  }
  /* Only a page that has read the figures asks again. */
  function again() { if (loading && !fresh(ONVIEW)) read(); }
  /* A script read with no page around it (a Postgres suite's figures)
     listens to nothing. */
  if (typeof document !== 'undefined' && document.addEventListener && typeof window !== 'undefined' && window.addEventListener) {
    document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'visible') again(); });
    window.addEventListener('focus', again);
    window.addEventListener('storage', function (e) { if (e.key === 'adspace-settings-at' && loading) read(); });
  }

  /* The tax codes a line may carry (2026-10-22, tax_codes_list): the team's
     alone, read once a page and again after a change. Each is { code, name,
     rate, active }; a line with none takes the client's SST. */
  var codes = null;
  function taxCodes(force) {
    if (codes && !force) return codes;
    var api = window.ADspaceAPI, db = api && api.client;
    if (!db) return Promise.resolve([]);
    var p = codes = db.rpc('tax_codes_list').then(function (r) {
      if (r.error || !r.data || r.data.error) { if (codes === p) codes = null; return []; }
      return r.data.codes || [];
    }).catch(function () { if (codes === p) codes = null; return []; });
    return p;
  }
  /* A code as a select names it: SV8 · 8% · Service tax. */
  function taxCodeWord(t) {
    return t.code + ' · ' + (Math.round(Number(t.rate) * 100) / 100) + '%' + (t.name && t.name !== t.code ? ' · ' + t.name : '');
  }

  /* The client's SST as Bukku names it (2026-11-12, the user: "follow
     bukku's"): the active tax code at the same rate, an SV code first, so
     a line's default reads SV8 · 8% and that code is not offered twice. */
  function sstCode(list, pct) {
    var hit = (list || []).filter(function (t) { return t.active !== false && Number(t.rate) === Number(pct); });
    hit.sort(function (a, b) { return (/^SV/i.test(b.code) ? 1 : 0) - (/^SV/i.test(a.code) ? 1 : 0) || String(a.code).localeCompare(String(b.code)); });
    return hit[0] || null;
  }
  // Malaysian service tax. One rate, because we are one entity.
  var TAX = { label: 'SST ' + FIRST.sst_pct + '%', rate: FIRST.sst_pct / 100 };

  function market(m) { return MARKETS[String(m || 'MY').toUpperCase()] || MARKETS.MY; }

  /* A rate is a whole number of dollars or ringgit; a total carries cents.
     Both line up in a column, which is why the caller pairs them with
     tabular figures. */
  function money(n, m, decimals) {
    var mk = market(m);
    var d = decimals === undefined ? 0 : decimals;
    return mk.sign + ' ' + Number(n || 0).toLocaleString(mk.locale,
      { minimumFractionDigits: d, maximumFractionDigits: d });
  }
  function money2(n, m) { return money(n, m, 2); }

  // Rounded to the cent at the point it is charged, not at the point it is
  // displayed, so a total and the sum of its lines cannot disagree.
  function taxOf(subtotal, m, applies, at) {
    if (applies === false) return 0;
    return cents(Number(subtotal || 0) * setting('sst_pct', at) / 100);
  }
  /* To the cent, a half away from nought, as the database rounds: a float
     product lands a hair under the half (1,234.50 x 0.95 is 1,172.7749…), so
     it is nudged before it is rounded, else the page charges a sen less than
     issue_letter works and the letter is refused as stale. */
  function cents(v) {
    var a = Math.round(Math.abs(v) * 100 + 1e-7) / 100;
    return v < 0 ? -a : a;
  }

  /* Term. Six months is the minimum a monthly service is sold on, so it is the
     baseline and costs nothing. A shorter term carries a margin the longer one
     would have earned, and a longer commitment earns a discount.

     The two are not the same operation, which is why they are stored as
     factors rather than as one percentage with a sign. A short term is priced
     to hold margin, so it divides (RM 1,000 over three months is
     RM 1,000 / 0.9 = RM 1,111.11 a month); a long term is a concession off the
     rate, so it multiplies (12 months is rate x 0.95). Writing "+10%" and
     "-5%" in one column hides that.

     A term the rate card does not name costs nothing either: a rule nobody has
     written is not one to invent at quoting time.

     `word` qualifies the figure on a line that carries the adjustment; `adj`
     names the adjustment on its own, for the control that asks whether to
     apply it, because a tick is named for what pressing it does. */
  var TERMS = {
    3:  { factor: 1 / 0.9,  word: '3-month commitment, 10% surcharge',     adj: '10% surcharge' },
    6:  { factor: 1,        word: '',                                      adj: '' },
    12: { factor: 0.95,     word: '12-month commitment, 5% discount',      adj: '5% discount' },
    24: { factor: 0.9,      word: '24-month commitment, 10% discount',     adj: '10% discount' }
  };
  function termOf(months) { return TERMS[Math.max(1, Number(months || 1))] || { factor: 1, word: '',                                      adj: '' }; }
  function termFactor(months) { return termOf(months).factor; }
  function termWord(months) { return termOf(months).word; }

  /* THE PERCENTAGE, FROM 2026-09-23. The rate card prices a term as a
     percentage on the rate now, by range rather than by exact month: one to
     three months carry 25% for the margin a short term costs, four and five
     carry 15%, six to eleven is the baseline, twelve and more earn 5% off and
     twenty-four and more 10% off. The figure is prefilled on the line from
     this table and is the person's to change (`client_services.term_pct`),
     because a client negotiates a term and the number on the letter is the
     number that was agreed, not the card's.

     What is stored decides how a line is read: a line carrying a percentage
     is billed at the rate times that percentage; a line carrying none is
     billed by the older factor table above, so a letter issued before the
     percentage existed redraws at the figure it printed. The three shapes a
     stored value can take are therefore all meaningful — a number, `0` for a
     term the person chose to leave unadjusted, and `null` for a line from
     before — and none of them is a default. */
  /* A term takes the longest commitment it has reached (the user,
     2026-11-17): under 3 months, then 3, 6, 12, 18 and 24 months; the
     percentage for each is a setting. The keys never move. */
  var TERM_PCT = [
    [1, 2, 'term_1_3'], [3, 5, 'term_4_5'], [6, 11, 'term_6_11'], [12, 17, 'term_12_23'], [18, 23, 'term_18_23'], [24, 999, 'term_24']
  ];
  function termPct(months, at) {
    var n = Math.max(1, Math.floor(Number(months || 1)));
    var k = termKey(n), v = k ? setting(k, at) : 0;
    if (v == null && k === 'term_18_23') v = setting('term_12_23', at);
    return v == null ? 0 : v;
  }
  /* The setting a term's adjustment is read from. */
  function termKey(months) {
    var n = Math.max(1, Math.floor(Number(months || 1)));
    for (var i = 0; i < TERM_PCT.length; i++) if (n >= TERM_PCT[i][0] && n <= TERM_PCT[i][1]) return TERM_PCT[i][2];
    return null;
  }
  /* The terms a quotation is offered on (the user, 2026-10-14), one list for
     Build quote and the quotation website; `quote_price` refuses any other
     (tests/quotes.js holds the two equal). */
  var QUOTE_TERMS = [3, 6, 12, 18, 24];
  function hasPct(pct) { return pct !== null && pct !== undefined && pct !== '' && !isNaN(Number(pct)); }
  /* The name of an adjustment, for the tick that applies it and the line
     that carries it: named for what it does to the figure, in the direction
     it goes, so "apply the 25% short term adjustment" and "apply the 5% long
     term discount" are never one unlabelled tick. */
  function pctAdj(pct) {
    var p = Number(pct);
    if (!p) return '';
    var shown = String(Math.round(Math.abs(p) * 100) / 100);
    return p > 0 ? shown + '% surcharge' : shown + '% discount';
  }
  function termAdj(months, pct) {
    if (hasPct(pct)) return pctAdj(pct);
    return termOf(months).adj || '';
  }
  /* The adjustment is asked for, never applied by itself. A line priced at
     RM 400 over three months printed RM 444.44 because the factor was applied
     to every line that had a term, so the rate somebody typed was not the rate
     on the screen and they had to work backwards from it to see their own
     figure. It is a tick on the line now (`client_services.term_adjust`).

     Only an explicit `false` turns it off, and that asymmetry is load bearing:
     an issued letter is a snapshot taken before the column existed, so its
     lines carry no flag at all, and a missing flag has to redraw the figure
     that was printed. New lines are stored with `false` and old ones were
     backfilled to `true`, so nothing is left to the default. */
  function adjusts(adjust) { return adjust !== false; }
  /* The rate the client is actually billed each month, rounded to the cent
     where it is charged so a monthly figure times its term cannot disagree
     with the total by a fraction of a sen. With a percentage on the line the
     rate carries it; without one the older factor table prices the term. */
  function rateFor(rate, months, adjust, pct) {
    if (!adjusts(adjust)) return cents(Number(rate || 0));
    var f = hasPct(pct) ? 1 + Number(pct) / 100 : termFactor(months);
    return cents(Number(rate || 0) * f);
  }
  /* The word beside the figure, which is only true where the tick is on: a
     line billed at the rate that was typed has nothing to explain. */
  function termNote(months, adjust, pct) {
    if (!adjusts(adjust)) return '';
    if (hasPct(pct)) {
      var adj = pctAdj(pct);
      return adj ? Math.max(1, Number(months || 1)) + '-month commitment, ' + adj : '';
    }
    return termWord(months);
  }

  // Named the same wherever it is charged, because it is the same tax.
  function taxLabel(m, at) {
    var p = setting('sst_pct', at);
    return 'SST ' + (Math.round(p * 100) / 100) + '%';
  }
  function signOf(m) { return market(m).sign; }
  /* The market a client's figures are written in (2026-10-22): SG only for
     a Singapore client billed in S$. A payload's `bill_market` is the
     database's own answer; a client row carries `market` and `bill_sgd`. */
  function curOf(c) {
    if (!c) return 'MY';
    if (c.bill_market) return String(c.bill_market).toUpperCase() === 'SG' ? 'SG' : 'MY';
    return String(c.market || '').toUpperCase() === 'SG' && c.bill_sgd ? 'SG' : 'MY';
  }
  /* A Singapore client billed in RM reads the S$ it comes to beside a
     total, at the rate set in Tax and terms (`fx_sgd`, RM to S$1):
     " (approximately S$ 952.38)". Nothing where the rate is unset, or for any
     other client. */
  /* `fx` is the rate a record kept (a letter's `bill_to.fx_sgd`), else
     the setting on `at`. `approxSgd` is the figure, null where none is
     said; one copy for every page and the Letter of Offer (2026-11-24). */
  function approxSgd(n, c, at, fx) {
    if (!c || String(c.market || '').toUpperCase() !== 'SG' || curOf(c) === 'SG') return null;
    if (n == null || n === '') return null;
    var r = Number(fx != null && fx !== '' ? fx : setting('fx_sgd', at)) || 0;
    var v = Number(n);
    if (!(r > 0) || !isFinite(v)) return null;
    return cents(v / r);
  }
  function approx(n, c, at, fx) {
    var v = approxSgd(n, c, at, fx);
    return v == null ? '' : ' (approximately ' + money2(v, 'SG') + ')';
  }
  /* SST said one way on every total (2026-10-18, review item 17): the
     Letter of Offer, the quotation's PDF, Build quote and /quote/ alike.
     Where it does not apply (a client exempt from it, 0%), its row reads
     SST not applicable, no figure says incl. or excl. SST, and the row
     before SST is left out, since it is the total. */
  function sstApplies(pct) { return Number(pct) > 0; }
  var SST_NONE = 'SST not applicable';
  /* The SST of a set of lines, each at its own tax code's rate where it
     carries one (a quotation line's `sst`, a letter line's `tax_pct`), else
     `dflt` (2026-10-22): whether any is charged, the row's words (one rate
     names it, two say SST), and what a line on another rate says under
     its amount where the rates differ: (+8% SST), (0% SST) (2026-10-23). */
  function sstOf(lines, dflt) {
    var rateOf = function (l) {
      var v = l.sst != null && l.sst !== '' ? l.sst : l.tax_pct;
      return v != null && v !== '' ? Number(v) : Number(dflt || 0);
    };
    var all = (lines || []).map(rateOf).filter(function (v, i, a) { return a.indexOf(v) === i; });
    var on = all.filter(function (v) { return v > 0; });
    var word = function (v) { return 'SST ' + (Math.round(v * 100) / 100) + '%'; };
    return {
      on: on.length > 0,
      word: !on.length ? SST_NONE : on.length === 1 ? word(on[0]) : 'SST',
      tag: function (l) {
        if (all.length < 2) return '';
        var v = Math.round(rateOf(l) * 100) / 100;
        return v > 0 ? '(+' + v + '% SST)' : '(0% SST)';
      }
    };
  }

  /* A quotation's totals as rows, one copy for Build quote, the
     quotation's PDF and the quotation website (2026-10-22, QT-4): each row
     [key, figure, is the total], the words each page's own. Where a monthly
     line runs months of its own the month's figures are the first month's,
     holding the one-time items too (2026-10-18); `on` says whether SST
     applies, so the excl. SST row is left out where it does not. Keys:
     monthSub, term, onceSub, firstExcl, monthExcl, sst, first, monthly,
     oneOff. */
  function quoteRows(t, lines, on) {
    t = t || {};
    var add = function (a, b) { return cents(Number(a || 0) + Number(b || 0)); };
    var own = Boolean(t.month) && (lines || []).some(function (l) { return l.basis === 'month' && l.months && Number(l.months) !== Number(t.term); });
    var r = [], o = t.once || {};
    if (t.month) {
      r.push(['monthSub', t.month.subtotal]);
      /* Each line its own term percentage (2026-11-15): a row a percentage,
         its words the fourth item (termLine), where the totals list them;
         a quotation made before reads its one row as it did. */
      if (Array.isArray(t.term_rows)) {
        t.term_rows.forEach(function (x) { if (Number(x.amount)) r.push(['term', x.amount, 0, termLine(x.months, x.pct), x]); });
      } else if (Number(t.term_pct)) r.push(['term', t.month.term]);
      if (own) {
        if (t.once) r.push(['onceSub', o.subtotal]);
        if (on) r.push(['firstExcl', add(t.month.excl, o.subtotal)]);
        r.push(['sst', add(t.month.sst, o.sst)], ['first', add(t.month.incl, o.incl), 1]);
      } else {
        if (on) r.push(['monthExcl', t.month.excl]);
        r.push(['sst', t.month.sst], ['monthly', t.month.incl, 1]);
      }
    }
    if (t.once && !own) r.push(['onceSub', t.once.subtotal], ['sst', t.once.sst], ['oneOff', t.once.incl, 1]);
    return r;
  }

  /* A quotation's lines as the client reads them (the user, 2026-11-06,
     option A: "include together as a plan instead breaking down as free"):
     a line the database marks `in_plan` (RM 0, Include in plan ticked)
     has no row of its own and is listed under the plan's inclusions,
     `{qty} × {label}` where more than one. One copy for the quotation's
     PDF and /quote/. */
  /* A package (QUOTATION PACKAGES, 2026-11-25) prints as one line: its
     contents and what it includes under its name, then what it does not
     include as a sentence (2026-11-25: "Advertising management is not
     included."). Never a rate of a piece inside it; the rate for one more
     piece is the quotation's Add-on Rates. */
  var PACK_WORDS = { not: function (list) {
    var w = list.map(function (x, i) { x = String(x || '').trim().replace(/[.;]+$/, ''); return i ? x.charAt(0).toLowerCase() + x.slice(1) : x; });
    var joined = w.length > 1 ? w.slice(0, -1).join(', ') + ' and ' + w[w.length - 1] : w[0];
    return joined + (w.length > 1 ? ' are' : ' is') + ' not included.';
  } };
  function packFold(l, cur, w) {
    if (l.kind !== 'package') return l;
    w = Object.assign({}, PACK_WORDS, w || {});
    var d = (l.detail || []).slice();
    if (l.excluded && l.excluded.length) d.push(w.not(l.excluded));
    l.detail = d;
    // folded once: a brand's own pass reads the words as they stand
    delete l.extra; delete l.excluded;
    return l;
  }
  /* An add-on's rate as the quotation states it (QUOTATION ADD-ON RATES):
     the card's unit after the figure, a unit ending ", from" read first
     ("Per trip, from" prints "from RM 450.00 per trip"). `zh` the Chinese. */
  function addonParts(r, cur) {
    var sign = String(cur || '').toUpperCase() === 'SGD' ? 'S$' : 'RM';
    var fig = sign + ' ' + Number(r && r.rate || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    var unit = String((r && r.unit) || '').trim(), from = /,\s*from$/i.test(unit);
    unit = unit.replace(/,\s*from$/i, '');
    return { from: from, fig: fig, unit: unit };
  }
  function addonRate(r, cur, zh) {
    var p = addonParts(r, cur), unit = p.unit;
    // the card's unit is English alone: a Chinese reader takes the figure
    if (zh) return (p.from ? '起价 ' : '') + p.fig;
    unit = unit.charAt(0).toLowerCase() + unit.slice(1);
    return (p.from ? 'from ' : '') + p.fig + (unit ? ' ' + unit : '');
  }

  function planFold(lines, cur, words) {
    lines = (lines || []).map(function (l) { return packFold(Object.assign({}, l), cur, words); });
    /* Several brands on one quotation (2026-11-24): each brand's lines fold
       into its own plan, the brands kept in their order. */
    if (lines.some(function (l) { return l.brand != null; })) {
      var seen = [];
      lines.forEach(function (l) { if (seen.indexOf(l.brand) < 0) seen.push(l.brand); });
      if (seen.length > 1) {
        return seen.reduce(function (out, b) {
          return out.concat(planFold(lines.filter(function (l) { return l.brand === b; }).map(function (l) { var c = Object.assign({}, l); delete c.brand; c._b = b; return c; }))
            .map(function (l) { var c = Object.assign({}, l); c.brand = c._b; delete c._b; return c; }));
        }, []);
      }
    }
    var plan = lines.filter(function (l) { return l.kind === 'plan'; })[0];
    if (!plan) return lines;
    var into = lines.filter(function (l) { return l.in_plan && l !== plan && l.basis !== 'once'; });
    if (!into.length) return lines;
    plan.detail = (plan.detail || []).concat(into.map(function (l) {
      /* "7 × Translation into Chinese": the count says what "per content
         piece" said. A quotation is a contract, so the count is stated for
         one as for many, and one reads singular: "1 × Additional reel, up
         to 60 seconds", never "Additional reels" (the user, 2026-11-07). */
      var name = String(l.label).replace(/, per [^,]+$/, '');
      var n = Math.max(1, Number(l.qty) || 1);
      if (n === 1) name = name.replace(/^(Additional )([a-z]+[^s])s\b/i, '$1$2');
      return n + ' × ' + name;
    }));
    /* Only the lines listed above leave the table: a one-time line a
       quotation of 6 or 7 Nov marked in_plan keeps its own row (audit
       2026-11-08, 2). */
    return lines.filter(function (l) { return into.indexOf(l) < 0; });
  }

  /* A quotation's term adjustment says what it is (the user, 2026-11-12):
     "6-month term discount (5%)" with its amount in minus, or "3-month term
     surcharge (15%)" in plus. One copy for Build quote, the quotation's
     PDF, /quote/ and the Letter of Offer; `zh` writes it in Chinese. */
  function termLine(n, pct, zh) {
    var p = Math.round(Math.abs(Number(pct) || 0) * 100) / 100, off = Number(pct) < 0;
    /* In Chinese for /quote/ (2026-11-24): 12个月合约优惠（5%）. */
    if (zh) return (n ? n + '个月' : '') + '合约' + (off ? '优惠' : '附加费') + '（' + p + '%）';
    return (n ? n + '-month ' : '') + 'term ' + (off ? 'discount' : 'surcharge') + ' (' + p + '%)';
  }
  /* The advertising budget's platforms (2026-11-12): the client's money
     paid to the platform on their behalf, never a service line. */
  var AD_PLATFORMS = [['meta', 'Meta'], ['tiktok', 'TikTok'], ['google', 'Google'], ['xhs', 'rednote'], ['youtube', 'YouTube'], ['linkedin', 'LinkedIn']];
  function adWord(k) {
    var hit = AD_PLATFORMS.filter(function (x) { return x[0] === k; })[0];
    return hit ? hit[1] : String(k || '');
  }
  /* Payment terms cover the whole quotation, NET 7 unless chosen. A term
     of 30 days or more is approved inside the team before the quotation is
     made (Build quote's Needs approval), so the PDF states it as decided
     (the user, 2026-11-12). */
  var PAY_DAYS = [7, 14, 30, 60, 90];

  window.ADspaceMoney = {
    termLine: termLine,
    sstCode: sstCode,
    AD_PLATFORMS: AD_PLATFORMS,
    adWord: adWord,
    PAY_DAYS: PAY_DAYS,
    planFold: planFold,
    addonRate: addonRate,
    addonParts: addonParts,
    quoteRows: quoteRows,
    money: money,
    money2: money2,
    taxOf: taxOf,
    taxLabel: taxLabel,
    taxCodes: taxCodes,
    taxCodeWord: taxCodeWord,
    sstApplies: sstApplies,
    SST_NONE: SST_NONE,
    sstOf: sstOf,
    termFactor: termFactor,
    termAdj: termAdj,
    termNote: termNote,
    termPct: termPct,
    termKey: termKey,
    QUOTE_TERMS: QUOTE_TERMS,
    rateFor: rateFor,
    cents: cents,
    sign: signOf,
    curOf: curOf,
    approx: approx,
    approxSgd: approxSgd,
    market: market,
    load: load,
    setting: setting,
    next: next,
    rows: function () { return ROWS.slice(); }
  };
})();
