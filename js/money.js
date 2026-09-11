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

  // Named the same wherever it is charged, because it is the same tax.
  function taxLabel() { return TAX.label; }
  function signOf(m) { return market(m).sign; }

  window.ADspaceMoney = {
    money: money,
    money2: money2,
    taxOf: taxOf,
    taxLabel: taxLabel,
    sign: signOf,
    market: market,
    MARKETS: MARKETS,
    TAX: TAX
  };
})();
