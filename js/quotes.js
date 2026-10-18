/* ADspace Digital Portal — a client's quotations (2026-10-14).
 *
 * A quotation is made from a selection and priced by the database alone
 * (`quote_preview` while it is ticked, `quotation_create` to keep it), from
 * the version of the rate card that is live, so the console, the website and
 * the PDF never disagree. It is kept as sent and never edited: Make a copy
 * prices the same selection again, and a client may hold several. Issue
 * Letter of Offer turns the chosen one's lines into the client's To quote
 * lines (`quotation_offer`) and opens the letter sheet on them.
 *
 * crm.js hands each call its context: { client, db, may(part, level),
 * esc, msg(id, text, kind), services, live (service id to letter number),
 * reload(done), offer(ids), undo(text, fn, host) }.
 */
(function () {
  'use strict';
  var MON = window.ADspaceMoney;
  var $ = function (id) { return document.getElementById(id); };
  function WA() { return window.ADspaceWhatsApp; }
  var esc = function (s) {
    return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  };
  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>';
  var PLAT = [['meta', 'Meta'], ['tiktok', 'TikTok'], ['rednote', 'rednote'], ['linkedin', 'LinkedIn']];
  var LANG = [['en', 'English'], ['zh', 'Chinese'], ['ms', 'Malay']];
  var SAID = {
    denied: 'This needs Clients: Services at Work.', 'client-scope': 'This client is outside your access.',
    'no-card': 'No rate card version is live. Publish one in Services.', 'bad-plan': 'That plan is not on the live rate card.',
    'no-platform': 'Choose at least one platform.',
    empty: 'Choose a plan, an advertising budget or a one-off item.', 'bad-extra': 'Additional contents are whole numbers.',
    'bad-once': 'One-off items are whole numbers.', 'not-found': 'This quotation is no longer available.',
    'not-proceeding': 'Restore this quotation before issuing a Letter of Offer from it.', 'bad-budget': 'Choose an advertising budget.',
    'bad-edit': 'Enter a whole quantity from 1, a rate of up to two decimals and 1 to 36 months.',
    expired: 'This quotation has expired. Make a copy to quote again.',
    'no-fx': 'Set the Singapore dollar rate in Tax and terms before quoting a Singapore client.'
  };
  function said(e) {
    if (!e) return '';
    var m = String(e.message || e);
    if (/could not find|does not exist|schema cache/i.test(m)) return 'This needs a database update.';
    return SAID[m] || m;
  }
  function rm(n) { return MON.money2(n, 'MY').replace(/^RM /, ''); }
  /* A Singapore client's quotation is in S$ (2026-10-15): the database
     prices it at the Tax and terms rate (`fx_sgd`, the ringgit to S$1) and
     marks its totals SGD. The card is in RM, so what Build quote shows from
     the card itself (a plan's fee, a step's rate, the budgets) is shown at
     the same rate: a rate to the cent, a budget in whole dollars. */
  var CUR = 'RM', FX = null;
  function curOf(q) { return q && q.totals && q.totals.currency === 'SGD' ? 'S$' : 'RM'; }
  function cv(n) { return FX ? Math.round(Number(n) / FX * 100) / 100 : Number(n); }
  function whole(n) { return Number(FX ? Math.round(Number(n) / FX) : n).toLocaleString('en-MY'); }
  function acct(n) { n = Number(n || 0); return n < 0 ? '(' + rm(-n) + ')' : rm(n); }

  /* What a quotation is now, worked out on every read: removed, a Letter of
     Offer issued from it, Not proceeding, requested by the client, valid, or
     past its day. */
  function stateOf(q, live) {
    if (q.removed_at) return ['Removed', 'is-off'];
    var held = (q._lines || []).map(function (id) { return live && live[id]; }).filter(Boolean)[0];
    if (held) return ['Letter of Offer issued', 'is-ok', held];
    if (q.status === 'not_proceeding') return ['Not proceeding', 'is-off'];
    var today = window.ADspaceClock.today();
    if (q.valid_until < today) return ['Expired', 'is-off'];
    if (q.status === 'requested') return ['Letter of Offer requested', 'is-warn'];
    return ['Valid until ' + window.ADspaceClock.date(q.valid_until).replace(/ \d{4}$/, ''), 'is-live'];
  }
  function monthly(q) { var m = q.totals && q.totals.month; return m ? m.incl : null; }
  /* A monthly line running months of its own makes the month's figures the
     first month's, named so (the user, 2026-10-18), as the Letter of Offer
     and the quotation's PDF name them. */
  function ownMonths(lines, t) {
    return (lines || []).some(function (l) { return l.basis === 'month' && l.months && Number(l.months) !== Number((t || {}).term); });
  }
  /* The first month holds the one-off items too (the user, 2026-10-18). */
  function sum2(a, b) { return Math.round((Number(a || 0) + Number(b || 0)) * 100) / 100; }
  function firstIncl(t) { return sum2(t.month.incl, t.once && t.once.incl); }
  function headline(q) {
    var m = monthly(q);
    var incl = MON.sstApplies((q.totals || {}).sst_pct) ? ' incl. SST' : '';
    if (m != null) return ownMonths(q.lines, q.totals) ? [curOf(q) + ' ' + rm(firstIncl(q.totals)), 'First month' + incl]
      : [curOf(q) + ' ' + rm(m), 'Monthly' + incl];
    var o = q.totals && q.totals.once;
    return o ? [curOf(q) + ' ' + rm(o.incl), incl ? 'One-off' + incl : 'One-off total'] : ['—', ''];
  }
  /* Every column but `billing`, which the table answers to nobody: the
     billing a prospect gave on the website is read through
     `quotation_billing`, at Clients: Billing (2026-10-14). */
  var COLS = 'id, ref, client_id, brand, version, version_id, selection, lines, totals, status, source, issued_at, ' +
    'valid_until, made_by, contact, access_key, requested_at, idem, removed_at, removed_by';
  function metaOf(q) {
    var t = q.totals || {};
    var bits = [];
    var plan = (q.lines || []).filter(function (l) { return l.kind === 'plan'; })[0];
    if (plan) bits.push(plan.label.replace(/^Social Media Services · /, ''));
    if (t.month) bits.push(t.term + ' months');
    bits.push((q.source === 'website' ? 'From the website' : 'Made by ' + (q.made_by || 'the team')) + ', ' +
      window.ADspaceClock.date(q.issued_at));
    return bits.join(' · ');
  }

  /* The client's quotations and, for each, the service lines made from it. */
  function load(ctx, done) {
    ctx.db.from('quotations').select(COLS).eq('client_id', ctx.client.id).order('issued_at', { ascending: false })
      .then(function (r) {
        if (r.error) { done(null, r.error); return; }
        var rows = r.data || [];
        rows.forEach(function (q) {
          q._lines = (ctx.services || []).filter(function (l) { return l.quotation_id === q.id; }).map(function (l) { return l.id; });
        });
        done(rows);
      }).catch(function (e) { done(null, e); });
  }

  var showRemoved = false;
  /* The Services pane's list: a row a quotation (the reference over what it
     is, the monthly figure, its state, a ⋯), the removed ones on asking. */
  function paint(host, ctx, rows) {
    var live = ctx.live || {};
    var shown = rows.filter(function (q) { return !q.removed_at; });
    var gone = rows.filter(function (q) { return q.removed_at; });
    var maySet = ctx.may('clients.services', 'work');
    var html = '<div class="viewhead qt-head"><span class="headmark"><h3>Quotations</h3></span>' +
      (maySet ? '<button class="btn btn-sm" id="qtBuild" type="button">' + PLUS + 'Build quote</button>' : '') + '</div>' +
      '<div class="msg" id="qtMsg"></div>';
    var list = shown.concat(showRemoved ? gone : []);
    if (!list.length) html += '<div class="empty">No quotations.</div>';
    else {
      html += '<div class="crm-table qt-table"><div class="crm-head svc-row qt-row"><span>Quotation</span>' +
        '<span class="svc-rate">Amount</span><span>State</span><span></span><span></span></div>' +
        list.map(function (q) {
          var st = stateOf(q, live), h = headline(q);
          var items = [];
          if (q.removed_at) items.push('<button class="kmenu-item" data-a="pdf" type="button"><b>Download</b></button>');
          /* Send on WhatsApp (2026-10-14): the quotation's PDF to a contact,
             drawn only once the template is on (`waOn` below). */
          if (WA() && WA().may('quotation') && !q.removed_at && q.status !== 'not_proceeding') {
            items.push('<button class="kmenu-item" data-a="wa" data-wa hidden type="button"><b>Send on WhatsApp</b></button>');
          }
          if (maySet && !q.removed_at) {
            if (st[0] !== 'Not proceeding' && st[0] !== 'Expired' && st[1] !== 'is-ok') items.push('<button class="kmenu-item" data-a="offer" type="button"><b>Issue Letter of Offer</b></button>');
            if (q.requested_at && ctx.billing && ctx.may('clients.billing', 'work')) items.push('<button class="kmenu-item" data-a="billing" type="button"><b>Use billing details</b></button>');
            items.push('<button class="kmenu-item" data-a="copy" type="button"><b>Make a copy</b></button>');
            items.push(q.status === 'not_proceeding'
              ? '<button class="kmenu-item" data-a="proceeding" type="button"><b>Restore</b></button>'
              : '<button class="kmenu-item" data-a="not_proceeding" type="button"><b>Not proceeding</b></button>');
            items.push('<button class="kmenu-item is-danger" data-a="remove" data-soft type="button"><b>Remove</b></button>');
          }
          if (maySet && q.removed_at) items.push('<button class="kmenu-item" data-a="restore" type="button"><b>Restore</b></button>');
          return '<div class="svc-row qt-row' + (q.removed_at || st[1] === 'is-off' ? ' is-off' : '') + '" data-id="' + esc(q.id) + '">' +
            '<span class="svc-name qt-name"><b class="qt-ref">' + esc(q.ref) + '</b><small>' + esc(metaOf(q)) + '</small></span>' +
            '<span class="svc-rate svc-amt qt-amt"><b>' + esc(h[0]) + '</b>' + (h[1] ? '<small>' + esc(h[1]) + '</small>' : '') + '</span>' +
            '<span class="qt-state"><span class="chip-state ' + st[1] + '">' + esc(st[0]) + '</span>' +
              (st[2] ? '<small>' + esc(st[2]) + '</small>' : '') + '</span>' +
            '<span class="qt-dl">' + (q.removed_at ? '' : '<button class="btn btn-sm" data-a="pdf" type="button">Download</button>') + '</span>' +
            '<span class="team-act">' + (items.length ? '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' +
              DOTS + '</button><div class="kmenu" data-menu hidden>' + items.join('') + '</div>' : '') + '</span></div>';
        }).join('') + '</div>';
    }
    if (gone.length) {
      html += '<button type="button" class="linkish crm-removed-toggle" id="qtGone">' +
        (showRemoved ? 'Hide ' : 'Show ') + gone.length + ' removed quotation' + (gone.length === 1 ? '' : 's') + '</button>';
    }
    host.innerHTML = html;
    host.hidden = false;
    var b = $('qtBuild');
    if (b) b.addEventListener('click', function () { build(ctx, null, b); });
    var g = $('qtGone');
    if (g) g.addEventListener('click', function () { showRemoved = !showRemoved; paint(host, ctx, rows); });
    if (host.querySelector('[data-wa]')) {
      WA().on('quotation').then(function (yes) {
        if (!yes) return;
        Array.prototype.forEach.call(host.querySelectorAll('[data-wa]'), function (it) { it.hidden = false; });
      });
    }
    Array.prototype.forEach.call(host.querySelectorAll('.qt-row[data-id]'), function (row) {
      var q = rows.filter(function (x) { return x.id === row.getAttribute('data-id'); })[0];
      var menu = row.querySelector('[data-menu]'), btn = row.querySelector('[data-a="menu"]');
      var dl = row.querySelector('.qt-dl [data-a="pdf"]');
      if (dl) dl.addEventListener('click', function () { act('pdf', q, ctx, host, dl); });
      if (!btn) return;
      btn.addEventListener('click', function () {
        var open = menu.hidden;
        Array.prototype.forEach.call(document.querySelectorAll('.kmenu'), function (m) { m.hidden = true; });
        menu.hidden = !open;
        btn.setAttribute('aria-expanded', String(open));
        if (open) window.ADspaceMenu.place(btn, menu);
      });
      Array.prototype.forEach.call(menu.querySelectorAll('[data-a]'), function (it) {
        it.addEventListener('click', function () {
          menu.hidden = true;
          act(it.getAttribute('data-a'), q, ctx, host, btn);
        });
      });
    });
  }

  function act(a, q, ctx, host, btn) {
    if (a === 'pdf') {
      if (!window.ADspaceQuotePdf) return;
      var tab = window.ADspaceDocs && window.ADspaceDocs.tabFor ? window.ADspaceDocs.tabFor() : null;
      window.ADspaceQuotePdf.draw(q, { attention: (q.contact && q.contact.name) || ctx.attention || '' }).then(function (blob) {
        window.ADspaceDocs.save(blob, window.ADspaceQuotePdf.fileName(q), tab);
      }).catch(function (e) {
        if (tab) try { tab.close(); } catch (x) {}
        ctx.msg('qtMsg', said(e) || 'Not drawn.', 'err');
      });
      return;
    }
    if (a === 'wa') {
      WA().compose({ purpose: 'quotation', clientId: q.client_id || (ctx.client && ctx.client.id), opener: btn,
        doc: { id: q.id, title: q.ref, file: function () {
          return window.ADspaceQuotePdf.draw(q, { attention: (q.contact && q.contact.name) || ctx.attention || '' })
            .then(function (blob) { return { blob: blob, name: window.ADspaceQuotePdf.fileName(q) }; });
        } },
        onSent: function (d, line) { ctx.msg('qtMsg', line, 'ok'); } });
      return;
    }
    if (a === 'copy') { build(ctx, q.selection, btn); return; }
    if (a === 'billing') {
      ctx.db.rpc('quotation_billing', { p_id: q.id }).then(function (r) {
        var d = r.data || {};
        if (r.error || d.error) { ctx.msg('qtMsg', said(r.error || d.error), 'err'); return; }
        ctx.billing(d, btn);
      }).catch(function (e) { ctx.msg('qtMsg', said(e), 'err'); });
      return;
    }
    if (a === 'offer') {
      ctx.db.rpc('quotation_offer', { p_id: q.id }).then(function (r) {
        var d = r.data || {};
        if (r.error || d.error) { ctx.msg('qtMsg', said(r.error || d.error), 'err'); return; }
        ctx.offer(d.ids || []);
      }).catch(function (e) { ctx.msg('qtMsg', said(e), 'err'); });
      return;
    }
    var back = { not_proceeding: 'proceeding', remove: 'restore' }[a];
    set(q, a, ctx, function () {
      if (!back) { ctx.msg('qtMsg', a === 'restore' || a === 'proceeding' ? 'Restored.' : 'Saved.', 'ok'); return; }
      ctx.undo(q.ref + (a === 'remove' ? ' removed.' : ' marked Not proceeding.'), function () {
        set(q, back, ctx, function () {});
      }, $('qtMsg'));
    });
  }
  function set(q, what, ctx, ok) {
    ctx.db.rpc('quotation_set', { p_id: q.id, p_what: what }).then(function (r) {
      var d = r.data || {};
      if (r.error || d.error) { ctx.msg('qtMsg', said(r.error || d.error), 'err'); return; }
      ctx.reload();
      ok();
    }).catch(function (e) { ctx.msg('qtMsg', said(e), 'err'); });
  }

  /* The Overview's section: three rows, read only. */
  function overview(rows, live) {
    var list = (rows || []).filter(function (q) { return !q.removed_at; }).slice(0, 3);
    if (!list.length) return '';
    return '<div class="qt-ov">' + list.map(function (q) {
      var st = stateOf(q, live), h = headline(q);
      return '<div class="qt-ovrow"><span class="svc-name qt-name"><b class="qt-ref">' + esc(q.ref) + '</b><small>' + esc(metaOf(q)) + '</small></span>' +
        '<span class="qt-ovend"><b>' + esc(h[0]) + '</b><span class="chip-state ' + st[1] + '">' + esc(st[0]) + '</span></span></div>';
    }).join('') + '</div>';
  }

  // ---- Build quote --------------------------------------------------------
  var B = null;   // the sheet's state while open
  function card(ctx, done) {
    ctx.db.rpc('rate_card_current').then(function (r) {
      if (r.error || !r.data) { done(null, r.error || 'no-card'); return; }
      done(r.data);
    }).catch(function (e) { done(null, e); });
  }
  function svcs(c, role) {
    return ((c.snapshot || {}).services || []).filter(function (s) {
      return s.active !== false && s.spec && s.spec.role === role;
    });
  }
  /* The rate card line an extra content is priced from, by what it is
     (`spec.kind`: a static graphic, a reel), never by its slug. */
  function extraSlug(kind) {
    var c = B.card && svcs(B.card, 'content').filter(function (x) { return x.spec.kind === kind; })[0];
    return c ? c.slug : null;
  }
  function feeOf(p) {
    var f = svcs(B.card, 'platform').filter(function (x) { return x.spec.platform === p; })[0];
    return f ? Number(f.rate) : 0;
  }
  function planOf() {
    return svcs(B.card, 'plan').filter(function (x) { return x.slug === B.plan; })[0] || null;
  }

  function build(ctx, sel, opener) {
    sel = sel || {};
    /* `edits`: a line's quantity, rate and months the team typed, by the
       line's key (2026-10-15, the user: "fully customised for the rates qty
       and months"); priced and kept by the database as typed. */
    B = { ctx: ctx, seq: 0, idem: null, plan: sel.plan || null, edits: JSON.parse(JSON.stringify(sel.edits || {})) };
    $('qbMsg').textContent = ''; $('qbMsg').className = 'msg';
    $('qbFor').textContent = (ctx.client.client_code ? ctx.client.client_code + ' · ' : '') + ctx.client.name;
    $('qbLines').innerHTML = ''; $('qbSum').textContent = '';
    FX = ctx.client.market === 'SG' ? Number(MON.setting('fx_sgd')) || 0 : null;
    CUR = FX == null ? 'RM' : 'S$';
    if (FX === 0) { ctx.msg('qtMsg', SAID['no-fx'], 'err'); B = null; return; }
    card(ctx, function (c, err) {
      if (!c) { ctx.msg('qtMsg', said(err) || 'No rate card version is live.', 'err'); B = null; return; }
      B.card = c;
      $('qbFor').textContent += ' · priced from v.' + c.version;
      var chosen = planOf();
      $('qbAds').value = chosen && chosen.spec.ads ? 'ads' : 'none';
      $('qbAds').dispatchEvent(new Event('input'));
      paintPlans();
      mixFor(sel.mix || 0);
      Array.prototype.forEach.call(document.querySelectorAll('#qbPlats input'), function (i) {
        i.checked = (sel.platforms || []).indexOf(i.value) > -1;
      });
      $('qbGraphic').value = String((sel.extra || {})[extraSlug('graphic')] || 0);
      $('qbReel').value = String((sel.extra || {})[extraSlug('reel')] || 0);
      Array.prototype.forEach.call(document.querySelectorAll('#qbLangs input'), function (i) {
        i.checked = (sel.langs || ['en']).indexOf(i.value) > -1;
      });
      $('qbTranslate').checked = Boolean(sel.translate);
      budgets(sel.budget == null ? 0 : sel.budget);
      var set = (c.snapshot || {}).settings || {};
      /* The five terms a quotation is offered on (2026-10-14), each with its
         adjustment as the rate card version holds it (18 months takes 12's
         on a version published before it had its own). */
      $('qbTerm').innerHTML = window.ADspaceMoney.QUOTE_TERMS.map(function (m) {
        var key = window.ADspaceMoney.termKey(m);
        var pct = Number((set[key] != null ? set[key] : key === 'term_18_23' ? set.term_12_23 : 0) || 0);
        return '<option value="' + m + '">' + m + ' months' + (pct ? ' · ' + (pct < 0 ? '−' : '+') + Math.abs(pct) + '%' : '') + '</option>';
      }).join('');
      $('qbTerm').value = String(sel.term || 6);
      var once = {};
      (sel.once || []).forEach(function (o) { once[o.slug] = o.qty; });
      $('qbOnce').innerHTML = ['content', 'verify', 'koc'].map(function (role) {
        return svcs(c, role).filter(function (s) { return s.rate != null; }).map(function (s) {
          /* A stepper a line, as the extra contents are: a count of one-off
             work is pressed up, never typed into a tall box. */
          var id = 'qbO-' + esc(s.slug), nm = esc(s.name);
          return '<div class="qb-step"><button class="iconbtn qb-stepbtn" type="button" data-step="-1" data-for="' + id + '" aria-label="One fewer ' + nm + '">' + MINUS + '</button>' +
            '<input class="qb-stepval" type="number" min="0" max="999" step="1" inputmode="numeric" id="' + id + '" data-slug="' + esc(s.slug) +
            '" value="' + esc(once[s.slug] || 0) + '" aria-label="' + nm + '">' +
            '<button class="iconbtn qb-stepbtn" type="button" data-step="1" data-for="' + id + '" aria-label="One more ' + nm + '">' + PLUS + '</button>' +
            '<span class="qb-stepname">' + nm + ' <small class="qb-rate">' + CUR + ' ' + esc(rm(cv(s.rate))) + ' each</small></span></div>';
        }).join('');
      }).join('');
      $('qbOnceMore').open = Boolean((sel.once || []).length);
      sync();
      window.ADspaceSheet.show($('qbBox'), { opener: opener || null });
      preview();
    });
  }

  /* The plans of the chosen kind as cards: the letter and its fee over its
     platforms and contents; the one chosen pressed again leaves no plan
     (advertising or one-off items alone). */
  var MINUS = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14"/></svg>';
  var PLUS = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>';
  function paintPlans() {
    var withAds = $('qbAds').value === 'ads';
    var list = svcs(B.card, 'plan').filter(function (p) { return Boolean(p.spec.ads) === withAds; });
    $('qbPlans').innerHTML = list.map(function (p) {
      var on = p.slug === B.plan;
      return '<button class="qb-plan' + (on ? ' is-on' : '') + '" type="button" role="radio" aria-checked="' + on + '" data-plan="' + esc(p.slug) + '">' +
        '<span class="qb-radio" aria-hidden="true"></span><span class="qb-plantext"><b>' + esc(p.spec.plan) + ' · ' + CUR + ' ' + esc(rm(cv(p.rate)).replace(/\.00$/, '')) +
        '</b><small>' + (p.spec.platforms === 1 ? '1 platform' : 'Up to ' + p.spec.platforms + ' platforms') + '</small>' +
        '<small>' + p.spec.contents + ' contents: ' + mixWords(p.spec.mix || [], true) + '</small>' +
        (p.spec.ad_budget ? '<small>Ad budget up to ' + esc(CUR + ' ' + whole(p.spec.ad_budget)) + '</small>' : '') +
        '</span></button>';
    }).join('');
  }
  /* The advertising budget follows the plan (the user, 2026-10-14): a plan
     with ads opens on the budget it covers, "included in the plan", and
     offers only the larger ones; with no such plan the list opens on None.
     The steps are the card's own (Meta advertising and the boosters). */
  /* The largest budget the live card covers, said where a larger one is on request. */
  function topBudget() {
    return svcs(B.card, 'ads').concat(svcs(B.card, 'booster')).reduce(function (m, x) { return Math.max(m, Number(x.spec.budget) || 0); }, 0);
  }
  function budgets(keep) {
    var p = planOf(), cover = p && p.spec.ad_budget ? Number(p.spec.ad_budget) : 0;
    var tiers = svcs(B.card, 'ads').concat(svcs(B.card, 'booster')).map(function (x) { return Number(x.spec.budget) || 0; })
      .filter(function (b, i, a) { return b > 0 && a.indexOf(b) === i; }).sort(function (a, b) { return a - b; });
    /* The values stay the card's (RM), which the database matches; the
       words are the client's currency. */
    var opts = [[0, cover ? 'Included: up to ' + CUR + ' ' + whole(cover) : 'None']];
    tiers.forEach(function (b) { if (b > cover) opts.push([b, 'Up to ' + CUR + ' ' + whole(b)]); });
    if (tiers.length) opts.push([-1, 'Above ' + CUR + ' ' + whole(tiers[tiers.length - 1]) + ' (on request)']);
    var val = String(keep == null ? $('qbBudget').value : keep);
    if (!opts.some(function (o) { return String(o[0]) === val; })) val = '0';
    $('qbBudget').innerHTML = opts.map(function (o) {
      return '<option value="' + o[0] + '"' + (String(o[0]) === val ? ' selected' : '') + '>' + esc(o[1]) + '</option>';
    }).join('');
    $('qbBudget').value = val;
  }
  /* What a plan's contents are, as the card prints them: "2 graphics, 4 reels"; two
     options read "or". */
  /* `html`: each part held whole (`6 reels` never breaks after its figure;
     2026-10-15, audit CLI-2), escaped. */
  function mixWords(mixes, html) {
    var part = function (t) { return html ? '<span class="qb-nb">' + esc(t) + '</span>' : t; };
    return mixes.map(function (m) {
      var w = [];
      if (m.graphic) w.push(part(m.graphic + (m.graphic === 1 ? ' graphic' : ' graphics')));
      if (m.reel) w.push(part(m.reel + (m.reel === 1 ? ' reel' : ' reels')));
      return w.join(', ');
    }).join(' or ');
  }
  function mixFor(at) {
    var p = planOf();
    var mixes = p ? p.spec.mix : [];
    $('qbMix').innerHTML = mixes.map(function (m, i) {
      var w = [];
      if (m.graphic) w.push(m.graphic + (m.graphic === 1 ? ' graphic' : ' graphics'));
      if (m.reel) w.push(m.reel + (m.reel === 1 ? ' reel' : ' reels'));
      return '<option value="' + i + '"' + (i === at ? ' selected' : '') + '>' + esc(w.join(' + ')) + '</option>';
    }).join('');
    /* One option is a fact read, never a disabled select. */
    $('qbMix').hidden = mixes.length < 2;
    $('qbMixOne').hidden = mixes.length !== 1;
    $('qbMixOne').textContent = mixes.length === 1 ? $('qbMix').options[0].textContent : '';
  }
  /* What cannot apply is hidden: the content, the extras and the languages
     need a plan. Beside each platform, what ticking it adds. */
  function sync() {
    var p = planOf();
    $('qbMixRow').hidden = !p || (p.spec.mix || []).length < 2;
    $('qbExtras').hidden = !p;
    $('qbLangCol').hidden = !p;
    /* With no plan the platforms and the budget and term take the width
       the plan's content, extras and languages leave. */
    $('qbThree').classList.toggle('is-bare', !p);
    $('qbMixRow').parentNode.classList.toggle('is-bare', $('qbMixRow').hidden);
    $('qbPlatsLabel').textContent = p ? 'Platforms (' + p.spec.platforms + ' in the plan)' : 'Platforms';
    var meta = feeOf('meta');
    var ticked = Array.prototype.filter.call(document.querySelectorAll('#qbPlats input'), function (i) { return i.checked; }).map(function (i) { return i.value; });
    Array.prototype.forEach.call(document.querySelectorAll('#qbPlats input'), function (i) {
      var f = feeOf(i.value), add = '';
      if (!i.checked) {
        if (!p) add = f;
        else if (ticked.length < p.spec.platforms) add = f > meta ? f - meta : '';
        else add = f;
      }
      i.parentNode.querySelector('.qb-rate').textContent = add ? '+' + cv(add).toLocaleString('en-MY') : '';
    });
  }
  /* A plan needs a platform: Meta is ticked for it where none is, and can
     be changed (prefilled, not fixed). */
  function prefillPlatform() {
    if (!B.plan) return;
    var box = document.querySelectorAll('#qbPlats input');
    if (Array.prototype.some.call(box, function (i) { return i.checked; })) return;
    Array.prototype.forEach.call(box, function (i) { if (i.value === 'meta') i.checked = true; });
  }
  function selection() {
    var sel = { plan: B.plan, term: Number($('qbTerm').value) || 6,
      platforms: [], langs: [], translate: $('qbTranslate').checked, budget: Number($('qbBudget').value) || 0, once: [] };
    if (sel.plan) sel.mix = Number($('qbMix').value) || 0;
    Array.prototype.forEach.call(document.querySelectorAll('#qbPlats input'), function (i) { if (i.checked) sel.platforms.push(i.value); });
    Array.prototype.forEach.call(document.querySelectorAll('#qbLangs input'), function (i) { if (i.checked) sel.langs.push(i.value); });
    if (sel.plan) {
      sel.extra = {};
      var g = Math.max(0, Math.floor(Number($('qbGraphic').value) || 0)), r = Math.max(0, Math.floor(Number($('qbReel').value) || 0));
      if (g && extraSlug('graphic')) sel.extra[extraSlug('graphic')] = g;
      if (r && extraSlug('reel')) sel.extra[extraSlug('reel')] = r;
    } else { sel.translate = false; }
    Array.prototype.forEach.call(document.querySelectorAll('#qbOnce input'), function (i) {
      var n = Math.max(0, Math.floor(Number(i.value) || 0));
      if (n) sel.once.push({ slug: i.getAttribute('data-slug'), qty: n });
    });
    if (Object.keys(B.edits).length) sel.edits = JSON.parse(JSON.stringify(B.edits));
    return sel;
  }
  /* The rates beside the extras and the translation come from the same
     answer that prices the lines. */
  function hints(d) {
    var x = (d && d.extra_rates) || {};
    var gs = extraSlug('graphic'), rs = extraSlug('reel');
    $('qbBox').querySelector('[data-rate-for="qbGraphic"]').textContent = gs && x[gs] != null ? CUR + ' ' + rm(x[gs]) + ' each' : '';
    $('qbBox').querySelector('[data-rate-for="qbReel"]').textContent = rs && x[rs] != null ? CUR + ' ' + rm(x[rs]) + ' each' : '';
    var p = planOf(), tr = svcs(B.card, 'language')[0];
    var n = p ? p.spec.contents + (Number($('qbGraphic').value) || 0) + (Number($('qbReel').value) || 0) : 0;
    var langs = document.querySelectorAll('#qbLangs input:checked').length;
    $('qbTrRate').textContent = p && tr && langs > 1 ? n * (langs - 1) + ' × ' + cv(tr.rate).toLocaleString('en-MY') : '';
  }
  var timer = null;
  function preview() {
    clearTimeout(timer);
    timer = setTimeout(function () {
      if (!B) return;
      var seq = ++B.seq;
      B.sel = selection();
      B.priced = null;
      $('qbSave').disabled = true;
      $('qbSum').textContent = '';
      /* The client named, so its SST exemption applies (2026-10-15, audit I1). */
      B.ctx.db.rpc('quote_preview', { p_sel: Object.assign({ client: B.ctx.client.id }, B.sel) }).then(function (r) {
        if (!B || seq !== B.seq) return;
        var d = r.data || {};
        hints(d);
        if (r.error || d.error) {
          $('qbLines').innerHTML = '<p class="ovnone">' + esc(said(r.error || d.error)) + '</p>';
          return;
        }
        B.priced = d;
        /* What was typed for a line the selection no longer holds is let go. */
        var keys = (d.lines || []).map(function (l) { return l.key; });
        Object.keys(B.edits).forEach(function (k) { if (keys.indexOf(k) < 0) delete B.edits[k]; });
        $('qbLines').innerHTML = table(d);
        $('qbSum').textContent = sumOf(d);
        $('qbSave').disabled = false;
      }).catch(function (e) { if (B && seq === B.seq) $('qbLines').innerHTML = '<p class="ovnone">' + esc(said(e)) + '</p>'; });
    }, 200);
  }
  /* The figure the person is choosing towards, kept in sight in the foot
     while the lines and totals sit at the sheet's end (2026-10-15). */
  function sumOf(d) {
    var t = (d && d.totals) || {}, out = [];
    var own = t.month && ownMonths(d && d.lines, t);
    if (t.month) out.push(CUR + ' ' + acct(own ? firstIncl(t) : t.month.incl) + (own ? ' first month' : ' monthly'));
    if (t.once && !own) out.push(CUR + ' ' + acct(t.once.incl) + ' one-off');
    return out.length ? out.join(' · ') + (MON.sstApplies(t.sst_pct) ? ' incl. SST' : '') : '';
  }
  /* The lines and the totals as the quotation will keep them. */
  function table(d) {
    var t = d.totals || {}, rows = d.lines || [];
    var out = '<div class="crm-table qb-table"><div class="crm-head svc-row qb-row"><span>Line</span><span class="svc-rate">Qty</span>' +
      '<span class="svc-rate">Rate (' + CUR + ')</span><span class="svc-rate">Months</span><span class="svc-rate">Subtotal (' + CUR + ')</span></div>' +
      rows.map(function (l) {
        /* Quantity, rate and months are typed where they are read; a line
           quoted off the card names the card's rate under it. */
        var sub = [];
        if (l.list_rate != null) sub.push('Rate card ' + CUR + ' ' + rm(l.list_rate));
        var box = function (what, v, cls, mode, label) {
          return '<input class="input input-sm qb-val ' + cls + '" type="text" inputmode="' + mode + '" data-noenter data-nodraft data-key="' +
            esc(l.key || '') + '" data-what="' + what + '" value="' + esc(v) + '" aria-label="' + esc(label + ', ' + l.label) + '">';
        };
        return '<div class="svc-row qb-row"><span class="svc-name qb-name">' + esc(l.label) + (sub.length ? '<small>' + esc(sub.join(' · ')) + '</small>' : '') + '</span>' +
          '<span class="svc-rate qb-qty"><span class="qb-lab">Qty</span>' + box('qty', l.qty, 'qb-qtyval', 'numeric', 'Quantity') + '</span>' +
          '<span class="svc-rate qb-rate"><span class="qb-lab">Rate (' + CUR + ')</span>' + box('rate', rm(l.rate), 'qb-rateval', 'decimal', 'Rate (' + CUR + ')') + '</span>' +
          '<span class="svc-rate qb-mo"><span class="qb-lab">Months</span>' + (l.basis === 'month' ? box('months', l.months || (d.totals || {}).term, 'qb-moval', 'numeric', 'Months') :
            '<span class="qb-once">One-off</span>') + '</span>' +
          '<span class="svc-rate qb-amt">' + esc(rm(l.amount)) + '</span></div>';
      }).join('') + '</div>';
    var tot = [], own = t.month && ownMonths(rows, t), o = t.once || {};
    /* SST said as the Letter of Offer says it (ADspaceMoney.sstApplies). */
    var sstOn = MON.sstApplies(t.sst_pct), incl = sstOn ? ' incl. SST' : '', sstRow = sstOn ? 'SST ' + t.sst_pct + '%' : MON.SST_NONE;
    var excl = function (label, v) { if (sstOn) tot.push([label + ' excl. SST', acct(v)]); };
    if (t.month) {
      tot.push(['Monthly subtotal', acct(t.month.subtotal)]);
      if (Number(t.term_pct)) tot.push([t.term + '-month ' + (t.term_pct < 0 ? 'commitment (' + Math.abs(t.term_pct) + '%)' : 'term (' + t.term_pct + '%)'), acct(t.month.term)]);
      if (own) {
        if (t.once) tot.push(['One-off subtotal', acct(o.subtotal)]);
        excl('First month', sum2(t.month.excl, o.subtotal));
        tot.push([sstRow, acct(sum2(t.month.sst, o.sst))], ['First month' + incl, CUR + ' ' + acct(firstIncl(t)), 1]);
      } else {
        excl('Monthly', t.month.excl);
        tot.push([sstRow, acct(t.month.sst)], ['Monthly' + incl, CUR + ' ' + acct(t.month.incl), 1]);
      }
    }
    if (t.once && !own) tot.push(['One-off subtotal', acct(t.once.subtotal)], [sstRow, acct(t.once.sst)], [sstOn ? 'One-off incl. SST' : 'One-off total', CUR + ' ' + acct(t.once.incl), 1]);
    out += '<dl class="qb-tot">' + tot.map(function (x) {
      return '<div' + (x[2] ? ' class="is-total"' : '') + '><dt>' + esc(x[0]) + '</dt><dd>' + esc(x[1]) + '</dd></div>';
    }).join('') + '</dl>';
    var notes = [];
    if (t.budget > 0) notes.push('Advertising budget of up to ' + CUR + ' ' + whole(t.budget) + ' per month is billed separately.');
    if ((d.on_request || []).length) notes.push('On request: ' + d.on_request.map(function (x) { return x === 'budget' ? 'advertising budget above ' + CUR + ' ' + whole(topBudget()) : x; }).join(', ') + '.');
    if (notes.length) out += '<p class="qb-note">' + esc(notes.join(' ')) + '</p>';
    return out;
  }

  function wire() {
    if (!$('qbBox') || wire.done) return;
    wire.done = true;
    var on = function () { if (!B) return; sync(); preview(); };
    $('qbAds').addEventListener('change', function () {
      if (!B || !B.card) return;
      var p = planOf();
      if (p && Boolean(p.spec.ads) !== (this.value === 'ads')) {
        var same = svcs(B.card, 'plan').filter(function (x) { return Boolean(x.spec.ads) === ($('qbAds').value === 'ads') && x.spec.platforms === p.spec.platforms; })[0];
        B.plan = same ? same.slug : null;
      }
      paintPlans(); mixFor(0); budgets(); on();
    });
    $('qbPlans').addEventListener('click', function (e) {
      var b = e.target.closest('[data-plan]');
      if (!b || !B) return;
      var slug = b.getAttribute('data-plan');
      B.plan = B.plan === slug ? null : slug;
      prefillPlatform();
      paintPlans(); mixFor(0); budgets(); on();
    });
    $('qbBox').addEventListener('click', function (e) {
      var b = e.target.closest('[data-step]');
      if (!b) return;
      var i = $(b.getAttribute('data-for'));
      i.value = String(Math.min(Number(i.max) || 99, Math.max(0, (Number(i.value) || 0) + Number(b.getAttribute('data-step')))));
      on();
    });
    ['qbMix', 'qbBudget', 'qbTerm', 'qbTranslate', 'qbGraphic', 'qbReel'].forEach(function (id) {
      $(id).addEventListener('change', on);
      $(id).addEventListener('input', on);
    });
    ['qbPlats', 'qbLangs', 'qbOnce'].forEach(function (id) { $(id).addEventListener('change', on); $(id).addEventListener('input', on); });
    /* A figure typed: Create waits for the figures it will keep; Enter or
       leaving the field prices it again. Empty, or the card's own figure,
       puts back the card's. */
    $('qbLines').addEventListener('input', function (e) {
      if (B && e.target.closest('.qb-val')) $('qbSave').disabled = true;
    });
    $('qbLines').addEventListener('keydown', function (e) {
      if (e.key === 'Enter' && !e.isComposing && e.target.closest('.qb-val')) { e.preventDefault(); e.target.blur(); }
    });
    $('qbLines').addEventListener('change', function (e) {
      var i = e.target.closest('.qb-val');
      if (!i || !B) return;
      var k = i.getAttribute('data-key'), what = i.getAttribute('data-what');
      var raw = String(i.value).replace(/[,\s]/g, '').replace(/^(RM|S\$)/i, '');
      var ok = what === 'rate' ? /^[0-9]{1,7}(\.[0-9]{1,2})?$/.test(raw) :
        what === 'qty' ? /^[0-9]{1,4}$/.test(raw) && Number(raw) >= 1 : /^[0-9]{1,2}$/.test(raw) && Number(raw) >= 1 && Number(raw) <= 36;
      var e1 = B.edits[k] || {};
      if (raw === '') delete e1[what];
      else if (ok) e1[what] = raw;
      else {
        $('qbMsg').textContent = SAID['bad-edit']; $('qbMsg').className = 'msg err';
        i.focus(); return;
      }
      if (Object.keys(e1).length) B.edits[k] = e1; else delete B.edits[k];
      $('qbMsg').textContent = ''; $('qbMsg').className = 'msg';
      preview();
    });
    $('qbCancel').addEventListener('click', function () { window.ADspaceSheet.close(); B = null; });
    $('qbClose').addEventListener('click', function () { $('qbCancel').click(); });
    $('qbSave').addEventListener('click', function () {
      if (!B || !B.priced) return;
      var go = this;
      B.idem = B.idem || (window.ADspaceDocs && window.ADspaceDocs.idemKey ? window.ADspaceDocs.idemKey() : String(Date.now()));
      go.disabled = true;
      B.ctx.db.rpc('quotation_create', { p_client: B.ctx.client.id, p_sel: B.sel, p_idem: B.idem }).then(function (r) {
        var d = r.data || {};
        go.disabled = false;
        if (r.error || d.error) { $('qbMsg').textContent = said(r.error || d.error); $('qbMsg').className = 'msg err'; return; }
        var ctx = B.ctx;
        window.ADspaceSheet.close();
        B = null;
        ctx.reload(function () { ctx.msg('qtMsg', d.ref + ' made.', 'ok'); });
      }).catch(function (e) { go.disabled = false; $('qbMsg').textContent = said(e); $('qbMsg').className = 'msg err'; });
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', wire); else wire();

  window.ADspaceQuotes = { load: load, paint: paint, overview: overview, build: build, stateOf: stateOf };
})();
