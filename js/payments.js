/* Payments (2026-11-19; the user: "analyze the pattern of each client /
 * entity to see their payment patterns, delays, how long they usually
 * transfer payments … to estimate and predicts the payments inwards
 * outwards"): Clients' third view, beside the list and Overdue invoices, at
 * Clients: Billing Full control. Everything is the database's answer
 * (`payment_analysis`, held to the clients the colleague sees) over the
 * last 24 months of Bukku's invoices, kept by `bukku-sync` every night and
 * on Read from Bukku: four figures (days sales outstanding, days to pay,
 * days paid late, paid on time), the open receivables by age, thirteen
 * weeks of money expected in and out, and a row a payer. One currency at a
 * time, never added across.
 *
 *   ADspacePayments.may()   — whether the view is offered
 *   ADspacePayments.on()    — whether it is on screen
 *   ADspacePayments.show(quiet) — draws it (Clients' view strip)
 *   ADspacePayments.hide()  — gives the list back
 */
(function () {
  'use strict';
  var API = window.ADspaceAPI;
  function db() { return API && API.client; }
  function $(id) { return document.getElementById(id); }
  function esc(s) { return window.ADspaceWords.esc(s); }
  function may(k, l) { var A = window.ADspaceAdmin; return Boolean(A && A.may && A.may(k, l)); }
  var UI = window.ADspaceState;
  var C = window.ADspaceClock;

  var SAID = {
    denied: 'You do not have permission to view Payments. Please ask an admin.',
    'needs-update': 'This feature is not available yet. Please contact an admin.',
    'bukku-not-set-up': window.ADspaceWords.line.bukkuNotSetUp,
    'bukku-token': 'Bukku is not available at the moment. Please contact an admin.',
    'bukku-unreachable': window.ADspaceWords.line.bukkuNoAnswer,
    'bukku-refused': window.ADspaceWords.line.bukkuRefused,
    failed: 'The request failed. Please try again.'
  };
  function said(d) { return (d && SAID[d.error]) || SAID.failed; }

  /* ---- Words ------------------------------------------------------------ */
  /* Money through js/money.js alone: RM and S$ by their market, any other
     currency by its code. */
  function money(n, cur, dp) {
    var M = window.ADspaceMoney;
    var s = M.money(n, cur === 'SGD' ? 'SG' : 'MY', dp == null ? 2 : dp);
    return cur && cur !== 'MYR' && cur !== 'SGD' ? s.replace(/^RM/, cur) : s;
  }
  function days(n) { return n == null ? '—' : (Math.round(Number(n) * 10) / 10) + (Number(n) === 1 ? ' day' : ' days'); }
  function pct(n) { return n == null ? '—' : Math.round(Number(n)) + '%'; }
  function day(d) { return d && C ? C.date(d + 'T00:00:00+08:00') : ''; }
  function short(d) { return d && C ? C.date(d + 'T00:00:00+08:00', { year: false }) : ''; }
  function plural(n, one, many) { return n + ' ' + (n === 1 ? one : many); }
  /* Better, Worse or Steady against the 12 months before (Analytics' one
     rule, `ADspaceSales.judge`). */
  function judge(now, before, good) {
    var S = window.ADspaceSales;
    if (!S || !S.judge || now == null || before == null) return null;
    return S.judge(Number(now), Number(before), good, 1);
  }

  /* ---- State ------------------------------------------------------------ */
  var st = { on: false, d: null, err: null, cur: null, q: '', loading: false, reading: false, wired: false };
  function mayView() { return may('clients.billing', 'manage') && Boolean(API && API.client); }

  function wire() {
    if (st.wired) return;
    st.wired = true;
    $('pynFind').addEventListener('input', function () { st.q = this.value.trim().toLowerCase(); paintPayers(); });
    $('pynCur').addEventListener('change', function () {
      if (this.value === st.cur) return;
      st.cur = this.value;
      load();
    });
    $('pynRead').addEventListener('click', readBukku);
  }
  function show(quiet) {
    if (!mayView()) return false;
    wire();
    var I = window.ADspaceInvoices;
    if (I && I.on()) I.hide();
    st.on = true;
    $('crmListView').hidden = true;
    $('pynView').hidden = false;
    if (I && I.strip) I.strip('payments');
    var A = window.ADspaceAdmin;
    if (!quiet && A && A.setUrl) A.setUrl();
    load();
    return true;
  }
  function hide() {
    st.on = false;
    if ($('pynView')) $('pynView').hidden = true;
  }

  function load() {
    if (st.loading) return;
    st.loading = true;
    if (!st.d) UI.skeleton($('pynBody'), 4);
    db().rpc('payment_analysis', { p_currency: st.cur || null }).then(function (r) {
      st.loading = false;
      if (r.error) { st.err = { error: /could not find|does not exist|schema cache/i.test(r.error.message || '') ? 'needs-update' : 'failed' }; st.d = null; paint(); return; }
      var d = r.data || {};
      if (d.error) { st.err = d; st.d = null; paint(); return; }
      st.err = null;
      st.d = d;
      st.cur = d.currency;
      paint();
    }).catch(function () { st.loading = false; st.err = { error: 'failed' }; st.d = null; paint(); });
  }
  /* Read from Bukku: the history read for a while, then the figures again. */
  function readBukku() {
    if (st.reading) return;
    st.reading = true;
    var b = $('pynRead'), msg = $('pynMsg');
    b.disabled = true;
    msg.textContent = ''; msg.className = 'msg';
    db().functions.invoke('bukku-sync', { body: { action: 'payments' } }).then(function (r) {
      if (r && r.data && r.data.error) return r.data;
      return API.fnRefusal(r).then(function (code) { return code ? { error: code } : (r.data || { error: 'failed' }); });
    }, function () { return { error: 'failed' }; }).then(function (d) {
      st.reading = false;
      b.disabled = false;
      if (d.error) { msg.textContent = said(d); msg.className = 'msg err'; return; }
      msg.textContent = d.more ? 'Read from Bukku. Earlier months were not read. Press Read from Bukku again.' : 'Read from Bukku.';
      msg.className = 'msg ok';
      load();
    });
  }

  /* ---- Drawing ---------------------------------------------------------- */
  function paint() {
    var body = $('pynBody');
    if (!st.on || !body) return;
    var cur = $('pynCur');
    if (st.err) {
      cur.hidden = true;
      $('pynCount').textContent = '';
      UI.failLine(body, 'Payments', said(st.err), function () { load(); });
      return;
    }
    var d = st.d;
    if (!d) return;
    var curs = d.currencies || [];
    cur.innerHTML = (curs.length ? curs : [d.currency]).map(function (c) {
      return '<option value="' + esc(c) + '"' + (c === d.currency ? ' selected' : '') + '>' + esc(c) + '</option>';
    }).join('');
    cur.hidden = curs.length < 2;
    if (window.ADspaceCmdbar) window.ADspaceCmdbar.refresh();
    var s = d.summary || {};
    if (!s.invoices) {
      $('pynCount').textContent = '';
      UI.emptyLine(body, 'No invoices.');
      return;
    }
    body.innerHTML = '<div class="ovw-kpis crm-tiles" id="pynTiles"></div>' +
      '<div class="pyn-charts"><div id="pynAging"></div><div id="pynWeeks"></div></div>' +
      '<div id="pynPayers"></div>' +
      '<p class="pyn-note">' + esc(noteOf(d)) + '</p>';
    paintTiles(d);
    paintCharts(d);
    paintPayers();
    if (UI.fit) UI.fit('#pynBody');
  }
  function noteOf(d) {
    var parts = ['Invoices from ' + day(d.from)];
    if (d.back_to && d.back_to > d.from) parts.push('Bukku history from ' + day(d.back_to));
    if (d.read_at) parts.push('Last read ' + C.date(d.read_at) + ', ' + C.clock(d.read_at));
    return parts.join(' · ') + '.';
  }
  function paintTiles(d) {
    var s = d.summary || {};
    var tile = function (label, fig, sub, trend) {
      return '<article class="chartcard ovw-kpi crm-tile"><span class="ovw-kpi-label">' + esc(label) + '</span>' +
        '<b class="ovw-kpi-fig">' + esc(fig) + '</b>' +
        '<span class="ovw-kpi-line' + (trend ? ' is-' + trend.tone : '') + '">' +
          (trend ? '<i class="ovw-kpi-arrow" aria-hidden="true">' + trend.arrow + '</i>' : '') +
          '<span class="ovw-kpi-sub">' + esc(sub) + '</span>' +
          (trend && trend.word ? '<span class="ovw-kpi-verdict">' + esc(trend.word) + '</span>' : '') + '</span></article>';
    };
    var trendOf = function (now, before, good) {
      if (now == null || before == null) return null;
      var v = judge(now, before, good), dd = Number(now) - Number(before);
      return { arrow: !dd ? '→' : dd > 0 ? '↗' : '↘', tone: v ? v.tone : 'off', word: v && dd ? v.word : '' };
    };
    var was = function (before, f) { return before == null ? '' : 'Was ' + f(before); };
    var tiles = [
      tile('Days sales outstanding', s.dso == null ? '—' : days(s.dso), money(s.open, d.currency) + ' unpaid'),
      tile('Days to pay', days(s.days_to_pay), was(s.days_to_pay_before, days) || plural(s.paid || 0, 'invoice paid', 'invoices paid'),
        trendOf(s.days_to_pay, s.days_to_pay_before, 'down')),
      tile('Days paid late', days(s.days_late), was(s.days_late_before, days) || '',
        trendOf(s.days_late, s.days_late_before, 'down')),
      tile('Paid on time', pct(s.on_time), was(s.on_time_before, pct) || '',
        trendOf(s.on_time, s.on_time_before, 'up'))
    ];
    var box = $('pynTiles');
    box.style.setProperty('--n', tiles.length);
    box.innerHTML = tiles.join('');
    if (window.ADspaceAdmin && window.ADspaceAdmin.figs) window.ADspaceAdmin.figs(box);
  }
  function paintCharts(d) {
    var s = d.summary || {}, a = s.aging || {}, CH = window.ADspaceChart, cur = d.currency;
    var fmt = function (v) { return money(v, cur); };
    /* The weeks are an estimate: whole ringgit, so the scale reads at a glance. */
    var whole = function (v) { return money(v, cur, 0); };
    CH.draw($('pynAging'), {
      kind: 'bars', title: 'Unpaid invoices by age', fmt: fmt, valueHead: 'Unpaid',
      rows: [
        { label: 'Not due', value: Number(a.current) || 0 },
        { label: '1 to 30 days', value: Number(a.d30) || 0 },
        { label: '31 to 60 days', value: Number(a.d60) || 0 },
        { label: '61 to 90 days', value: Number(a.d90) || 0 },
        { label: 'Over 90 days', value: Number(a.over90) || 0, tone: Number(a.over90) > 0 ? 'err' : '' }
      ],
      empty: 'No unpaid invoices.'
    });
    var weeks = d.weeks || [];
    CH.draw($('pynWeeks'), {
      kind: 'columns', title: 'Next 13 weeks', fmt: whole,
      series: [{ label: 'Money in' }, { label: 'Money out', tone: 'mute' }],
      cats: weeks.map(function (w) {
        return { label: short(w.start), long: 'Week of ' + day(w.start), values: [Number(w.in) || 0, Number(w.out) || 0] };
      }),
      empty: 'Nothing expected.'
    });
    var later = d.later || {};
    var tot = weeks.reduce(function (o, w) { o.i += Number(w.in) || 0; o.o += Number(w.out) || 0; return o; }, { i: 0, o: 0 });
    var foot = document.createElement('dl');
    foot.className = 'ovfacts pyn-sum';
    var fact = function (k, v, late) { return '<div><dt>' + esc(k) + '</dt><dd' + (late ? ' class="is-late"' : '') + '>' + esc(v) + '</dd></div>'; };
    foot.innerHTML = fact('Money in', fmt(tot.i)) + fact('Money out', fmt(tot.o)) + fact('Net', fmt(tot.i - tot.o), tot.i - tot.o < 0) +
      (Number(later.in) || Number(later.out) ? fact('After 13 weeks', fmt(Number(later.in) || 0) + ' in · ' + fmt(Number(later.out) || 0) + ' out') : '');
    var card = $('pynWeeks').querySelector('.chartcard');
    if (card) card.insertBefore(foot, card.querySelector('.chart-data'));
  }
  function shown() {
    var q = st.q;
    return ((st.d && st.d.payers) || []).filter(function (p) {
      return !q || [p.name, p.client_name || '', p.code || ''].join(' ').toLowerCase().indexOf(q) > -1;
    });
  }
  function paintPayers() {
    var box = $('pynPayers');
    if (!box || !st.d) return;
    var rows = shown(), all = (st.d.payers || []).length;
    $('pynCount').textContent = all ? (st.q ? rows.length + ' of ' + all : plural(all, 'payer', 'payers')) : '';
    box.innerHTML = '';
    var G = window.ADspaceGroup;
    if (!rows.length) { UI.emptyLine(box, st.q ? 'No matches.' : 'No payers.'); return; }
    box.appendChild(G.section({
      route: 'payments', key: 'payers', name: 'Payers', count: rows.length, shut: false,
      table: function () {
        var t = document.createElement('div');
        t.className = 'crm-table softpanel pyn-table';
        t.innerHTML = '<div class="pyn-row crm-head prow"><span>Payer</span><span class="pyn-n">Days to pay</span><span class="pyn-n">Days late</span>' +
          '<span class="pyn-n">On time</span><span class="pyn-n">Unpaid</span><span>Trend</span></div>';
        G.more(t, rows, 30, '', rowOf);
        return t;
      }
    }));
  }
  function rowOf(p) {
    var cur = st.d.currency;
    var v = judge(p.days_late, p.late_before, 'down');
    var trend = v ? '<span class="anl-verdict is-' + esc(v.tone) + '">' + esc(v.word) + '</span>' : '<span class="muted">—</span>';
    var row = document.createElement(p.client ? 'button' : 'div');
    if (p.client) { row.type = 'button'; row.setAttribute('aria-label', p.name + ', open billing'); }
    row.className = 'crm-row pyn-row prow';
    var meta = [];
    if (p.client_name && p.client_name !== p.name) meta.push(p.client_name);
    else if (!p.client) meta.push('Not linked to a client');
    meta.push(plural(Number(p.invoices) || 0, 'invoice', 'invoices'));
    var phone = [days(p.days_to_pay) + ' to pay', pct(p.on_time) + ' on time'];
    row.innerHTML = '<span class="pyn-who pr-main"><b>' + esc(p.name) + '</b><small>' +
        meta.map(function (m) { return '<span class="inv-part">' + esc(m) + '</span>'; }).join(' · ') +
        '<span class="pyn-m"> · ' + phone.map(function (m) { return '<span class="inv-part">' + esc(m) + '</span>'; }).join(' · ') + '</span></small></span>' +
      '<span class="pyn-n">' + esc(days(p.days_to_pay)) + '</span>' +
      '<span class="pyn-n' + (Number(p.days_late) > 0 ? ' is-late' : '') + '">' + esc(days(p.days_late)) + '</span>' +
      '<span class="pyn-n">' + esc(pct(p.on_time)) + '</span>' +
      '<span class="pyn-n pyn-open pr-end">' + (Number(p.open) > 0 ? esc(money(p.open, cur)) +
        (Number(p.overdue) > 0 ? '<small class="is-late">' + esc(money(p.overdue, cur)) + ' overdue</small>' : '') : '<span class="muted">—</span>') + '</span>' +
      '<span class="pyn-trend pr-state">' + trend + '</span>';
    if (p.client) row.addEventListener('click', function () {
      history.pushState(null, '', '/admin/?client=' + encodeURIComponent(p.slug || p.client) + '&tab=billing');
      hide();
      var A = window.ADspaceAdmin;
      if (A && A.restore) A.restore(); else location.reload();
    });
    return row;
  }

  window.ADspacePayments = { may: mayView, on: function () { return st.on; }, show: show, hide: hide };
})();
