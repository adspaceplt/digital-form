/*
 * Money, for a portal that bills in two countries.
 *
 * Every figure used to be printed with "RM" in front of it, which was wrong
 * the moment a Singapore client opened their page. Currency follows the
 * client's market and nothing else decides it.
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

  // Malaysian service tax. One rate, because we are one entity.
  var TAX = { label: 'SST 8%', rate: 0.08 };

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
  function taxOf(subtotal, m, applies) {
    if (applies === false) return 0;
    return Math.round(Number(subtotal || 0) * TAX.rate * 100) / 100;
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
    3:  { factor: 1 / 0.9,  word: '3 month term, 10% short term adjustment', adj: '10% short term adjustment' },
    6:  { factor: 1,        word: '',                                        adj: '' },
    12: { factor: 0.95,     word: '12 month term, 5% discount',              adj: '5% long term discount' },
    24: { factor: 0.9,      word: '24 month term, 10% discount',             adj: '10% long term discount' }
  };
  function termOf(months) { return TERMS[Math.max(1, Number(months || 1))] || { factor: 1, word: '', adj: '' }; }
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
  var TERM_PCT = [
    [1, 3, 25], [4, 5, 15], [6, 11, 0], [12, 23, -5], [24, 999, -10]
  ];
  function termPct(months) {
    var n = Math.max(1, Math.floor(Number(months || 1)));
    for (var i = 0; i < TERM_PCT.length; i++) {
      if (n >= TERM_PCT[i][0] && n <= TERM_PCT[i][1]) return TERM_PCT[i][2];
    }
    return 0;
  }
  function hasPct(pct) { return pct !== null && pct !== undefined && pct !== '' && !isNaN(Number(pct)); }
  /* The name of an adjustment, for the tick that applies it and the line
     that carries it: named for what it does to the figure, in the direction
     it goes, so "apply the 25% short term adjustment" and "apply the 5% long
     term discount" are never one unlabelled tick. */
  function pctAdj(pct) {
    var p = Number(pct);
    if (!p) return '';
    var shown = String(Math.round(Math.abs(p) * 100) / 100);
    return p > 0 ? shown + '% short term adjustment' : shown + '% long term discount';
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
    if (!adjusts(adjust)) return Math.round(Number(rate || 0) * 100) / 100;
    var f = hasPct(pct) ? 1 + Number(pct) / 100 : termFactor(months);
    return Math.round(Number(rate || 0) * f * 100) / 100;
  }
  /* The word beside the figure, which is only true where the tick is on: a
     line billed at the rate that was typed has nothing to explain. */
  function termNote(months, adjust, pct) {
    if (!adjusts(adjust)) return '';
    if (hasPct(pct)) {
      var adj = pctAdj(pct);
      return adj ? Math.max(1, Number(months || 1)) + ' month term, ' + adj : '';
    }
    return termWord(months);
  }

  // Named the same wherever it is charged, because it is the same tax.
  function taxLabel() { return TAX.label; }
  function signOf(m) { return market(m).sign; }

  window.ADspaceMoney = {
    money: money,
    money2: money2,
    taxOf: taxOf,
    taxLabel: taxLabel,
    termFactor: termFactor,
    termWord: termWord,
    termAdj: termAdj,
    termNote: termNote,
    termPct: termPct,
    rateFor: rateFor,
    TERMS: TERMS,
    TERM_PCT: TERM_PCT,
    sign: signOf,
    market: market,
    MARKETS: MARKETS,
    TAX: TAX
  };
})();
