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
  function termAdj(months) { return termOf(months).adj || ''; }
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
     with the total by a fraction of a sen. */
  function rateFor(rate, months, adjust) {
    var f = adjusts(adjust) ? termFactor(months) : 1;
    return Math.round(Number(rate || 0) * f * 100) / 100;
  }
  /* The word beside the figure, which is only true where the tick is on: a
     line billed at the rate that was typed has nothing to explain. */
  function termNote(months, adjust) { return adjusts(adjust) ? termWord(months) : ''; }

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
    rateFor: rateFor,
    TERMS: TERMS,
    sign: signOf,
    market: market,
    MARKETS: MARKETS,
    TAX: TAX
  };
})();
