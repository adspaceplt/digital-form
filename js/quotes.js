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
  var esc = window.ADspaceWords.esc;
  var wholeDays = function (h) { return String(h).replace(/\b(\d{1,2}) ([A-Z][a-z]{2,3}) (\d{4})\b/g, '$1\u00a0$2\u00a0$3'); };
  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>';
  var SAID = {
    denied: 'This needs Clients: Quotations at Manage.', 'client-scope': 'This client is outside your access.',
    'no-card': 'No rate card version is live. Publish one in Services.', 'bad-plan': 'That plan is not on the live rate card.',
    'no-platform': 'Choose at least one platform.',
    empty: 'Choose a plan, an advertising budget or a one-off item.', 'nothing-priced': 'Add an item with a listed rate. Items quoted on request cannot form a quotation on their own.', revised: 'This quotation has been revised. Send the revised quotation instead.', 'bad-extra': 'Additional content pieces are whole numbers.',
    'bad-once': 'One-off items are whole numbers.', 'not-found': 'This quotation is no longer available.',
    'not-proceeding': 'Restore this quotation before issuing a Letter of Offer from it.', 'bad-budget': 'Choose an advertising budget.',
    'bad-edit': 'Enter a whole quantity from 1, a rate of up to two decimals and 1 to 36 months.',
    'bad-tax': 'That tax code is no longer offered. Choose another.',
    expired: 'This quotation has expired. Duplicate it to quote again.',
    'not-sent': 'Send the quotation first.', 'no-contact': 'This prospect is marked Do not contact. Choose Allow contact first.',
    'wa-off': 'The Quotation ready WhatsApp template is off. Turn it on in Settings, Templates.',
    'no-number': 'No WhatsApp number is held for this prospect.',
    'no-fx': 'Set the Singapore dollar rate in Tax and terms before quoting a Singapore client.',
    /* Signing, submitting and reviewing (QUOTATION SIGNING, 2026-10-31). */
    'not-signed': 'This quotation has not been signed.', signed: 'This quotation has already been signed. Refresh the page.',
    reviewed: 'This quotation has already been reviewed. Refresh the page.',
    'in-review': 'This quotation is already with its reviewer. Refresh the page.',
    'bad-reviewer': 'Choose a reviewer with Clients: Quotations at Full Access.', own: 'Choose a reviewer other than yourself.',
    'not-submitted': 'This quotation is not waiting for review. Refresh the page.',
    'not-reviewer': 'Only the reviewer chosen, or an admin, approves this quotation.',
    'note-required': 'Enter what needs correcting.',
    'billing-access': 'Approving fills Billing, which needs Clients: Billing at Work. Ask the reviewer chosen, or an admin.',
    'bad-day': 'Choose the day it was signed, from the day it was issued to today.',
    'bad-scan': 'Enter the scan as a web address starting https://.',
    'bad-legal_name': 'Enter the registered name.', 'bad-company_no': 'Enter the registration number: 6 to 20 letters or digits.',
    'bad-company_no_old': 'Enter the old registration number: 4 to 20 letters or digits.',
    'bad-tin': 'Enter the TIN: 6 to 20 letters or digits.', 'bad-sst_no': 'Enter the SST number: 6 to 25 letters or digits.',
    'bad-billing_address': 'Enter the billing address in full.', 'bad-finance_email': 'Enter a valid email address.',
    'bad-contact_salutation': 'Choose a salutation from the list.', 'bad-contact_name': 'Enter the billing contact\'s name.',
    'bad-contact_phone': 'Enter the billing contact\'s phone number.', 'bad-contact_email': 'Enter a valid email address.',
    'bad-signer_name': 'Enter the name of the person who signed.', 'bad-signer_designation': 'Enter their designation.'
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
  /* To the cent as quote_fx_snap rounds (a half away from nought; the audit
     of 2026-10-26, finding 13). */
  function cv(n) { return FX ? MON.cents(Number(n) / FX) : Number(n); }
  function whole(n) { return Number(FX ? Math.round(Number(n) / FX) : n).toLocaleString('en-MY'); }
  function acct(n) { n = Number(n || 0); return n < 0 ? '(' + rm(-n) + ')' : rm(n); }

  /* What a quotation is now, worked out on every read: removed, a Letter of
     Offer issued from it, cancelled, requested by the client, valid, or
     past its day. */
  function stateOf(q, live) {
    if (q.removed_at) return ['Removed', 'is-off'];
    /* Signed on its link or on paper, then checked, submitted and reviewed
       (QUOTATION SIGNING, 2026-10-31): the signing outranks the date, since
       a signed quotation is held to as signed. */
    if (q.reviewed_at) return ['Accepted', 'is-ok', 'Reviewed by ' + (q.reviewed_by || '')];
    if (q.signed_at) {
      if (q.returned_at) return ['Sent back', 'is-danger', 'By ' + (q.returned_by || '')];
      if (q.submitted_at) return ['In review', 'is-warn', q.reviewer_name || ''];
      return ['Signed', 'is-warn', 'By ' + (((q.signed || {}).signer || {}).name || '')];
    }
    var held = (q._lines || []).map(function (id) { return live && live[id]; }).filter(Boolean)[0];
    if (held) return ['Letter of Offer issued', 'is-ok', held];
    if (q.status === 'not_proceeding') return ['Cancelled', 'is-off'];
    /* A later quotation made from this one revises it; the prospect's link
       shows that one (2026-10-26). */
    if (q._revised) return ['Revised', 'is-off', 'By ' + q._revised];
    /* A website quotation waits for the team before the prospect sees the
       price (2026-10-29). */
    if (awaiting(q)) return ['Awaiting review', 'is-warn', q.reply_due ? 'Send by ' + window.ADspaceClock.date(window.ADspaceClock.day(q.reply_due)).replace(/ \d{4}$/, '') : ''];
    var today = window.ADspaceClock.today();
    if (q.valid_until < today) return ['Expired', 'is-off'];
    if (q.status === 'requested') return ['Letter of Offer requested', 'is-warn'];
    if (q.proceed_at) return ['Ready to proceed', 'is-warn', 'Contact by ' + window.ADspaceClock.date(window.ADspaceClock.day(q.proceed_due)).replace(/ \d{4}$/, '')];
    return ['Valid until ' + window.ADspaceClock.date(q.valid_until).replace(/ \d{4}$/, ''), 'is-live'];
  }
  function awaiting(q) { return q.source === 'website' && !q.released_at && !q._revised && !q.removed_at && q.status !== 'not_proceeding'; }
  /* A quotation that can still become a Letter of Offer: valid, or the
     client has asked for the letter (2026-10-22, QT-M1). */
  function offerable(q, live) {
    if (q.removed_at) return false;
    var st = stateOf(q, live);
    return st[1] === 'is-live' || st[0] === 'Letter of Offer requested' || st[0] === 'Ready to proceed';
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
    var incl = MON.sstOf(q.lines, (q.totals || {}).sst_pct).on ? ' incl. SST' : '';
    if (m != null) return ownMonths(q.lines, q.totals) ? [curOf(q) + ' ' + rm(firstIncl(q.totals)), 'First month' + incl]
      : [curOf(q) + ' ' + rm(m), 'Monthly' + incl];
    var o = q.totals && q.totals.once;
    return o ? [curOf(q) + ' ' + rm(o.incl), incl ? 'One-off' + incl : 'One-off total'] : ['—', ''];
  }
  var COLS = 'id, ref, client_id, brand, version, version_id, selection, lines, totals, status, source, issued_at, ' +
    'valid_until, made_by, contact, access_key, requested_at, removed_at, removed_by, proceed_at, proceed_due, proceed_start, proceed_decider, replaces, no_contact_at, released_at, reply_due, ' +
    'signed_at, signed, submitted_at, submitted_by, reviewer_id, reviewer_name, reviewed_at, reviewed_by, reviewed_role, returned_at, return_note, returned_by, sign_history';
  /* Two short lines (2026-10-26, the user: "too many info"): what it is, then
     where it came from and when. */
  function metaOf(q) {
    var t = q.totals || {};
    var bits = [];
    var plan = (q.lines || []).filter(function (l) { return l.kind === 'plan'; })[0];
    if (plan) bits.push(plan.label.replace(/^Social Media Services · /, '').replace(/ \(.*\)$/, ''));
    if (t.month) bits.push(t.term + ' months');
    if (!bits.length) bits.push('One-off');
    return bits.join(' · ');
  }
  function fromOf(q) {
    return (q.source === 'website' ? 'Website' : q.made_by || 'The team') + ' · ' + window.ADspaceClock.date(q.issued_at) +
      (q._revises ? ' · revises ' + q._revises : '');
  }

  /* The client's quotations and, for each, the service lines made from it. */
  function load(ctx, done) {
    ctx.db.from('quotations').select(COLS).eq('client_id', ctx.client.id).order('issued_at', { ascending: false })
      .then(function (r) {
        if (r.error) { done(null, r.error); return; }
        var rows = r.data || [];
        rows.forEach(function (q) {
          q._lines = (ctx.services || []).filter(function (l) { return l.quotation_id === q.id; }).map(function (l) { return l.id; });
          var by = rows.filter(function (x) { return x.replaces === q.id && !x.removed_at; })[0];
          q._revised = by ? by.ref : null;
          var of = rows.filter(function (x) { return x.id === q.replaces; })[0];
          q._revises = of ? of.ref : null;
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
    var maySet = ctx.may('clients.quotes', 'work');
    /* Delete, a removed quotation's alone, is Full Access (2026-10-31). */
    var mayDelete = ctx.may('clients.quotes', 'manage');
    /* Issue Letter of Offer makes service lines and a letter (2026-10-22). */
    var mayOffer = maySet && ctx.may('clients.services', 'work') && ctx.may('clients.documents', 'work');
    var html = '<div class="viewhead qt-head"><span class="headmark"><h3>Quotations</h3></span>' +
      (maySet ? '<button class="btn btn-sm" id="qtBuild" type="button">' + PLUS + 'Build quote</button>' : '') + '</div>' +
      '<div class="msg" id="qtMsg"></div>';
    var list = shown;
    /* An empty list carries its way out (2026-10-22, SL-M2). */
    if (!list.length) html += '<div class="empty has-go"><span>No quotations.</span>' +
      (maySet ? '<button class="btn btn-sm" data-a="build" type="button">' + PLUS + 'Build quote</button>' : '') + '</div>';
    else {
      html += '<div class="crm-table qt-table"><div class="crm-head svc-row qt-row"><span>Quotation</span>' +
        '<span class="svc-rate">Amount</span><span>State</span><span></span><span></span></div>' +
        list.map(function (q) {
          var st = stateOf(q, live), h = headline(q);
          var items = [];
          if (q.removed_at) items.push('<button class="kmenu-item" data-g="1" data-a="pdf" type="button" role="menuitem">Download</button>');
          /* Preview PDF (2026-10-31): the file in a tab to read before it is
             sent, beside the row's Download. */
          else items.push('<button class="kmenu-item" data-g="1" data-a="view" type="button" role="menuitem">Preview PDF</button>');
          /* The prospect's own page (2026-10-30): Preview opens it read only,
             for any reader of the quotation; Preview is the team's view,
             Copy link the prospect's. */
          if (q.access_key && !q.removed_at) items.push('<button class="kmenu-item" data-g="1" data-a="preview" type="button" role="menuitem">Preview</button>');
          /* Its own link, to send the prospect again by hand, once the team
             has sent the quotation (2026-10-30); a team's quotation has one
             too, made at the first Copy link, so the client signs on it
             (QUOTATION SIGNING, 2026-10-31). */
          if (!q.removed_at && !awaiting(q) && !q._revised && q.status !== 'not_proceeding' && (q.access_key || maySet)) {
            items.push('<button class="kmenu-item" data-g="1" data-a="link" type="button" role="menuitem">Copy link</button>');
          }
          /* Send on WhatsApp (2026-10-14): the quotation's PDF to a contact,
             drawn only once the template is on (`waOn` below). */
          /* What a quotation that can be offered asks next is on its row,
             beside Download (2026-10-22, QT-M1): Issue Letter of Offer. The
             ⋯ keeps the rest. */
          var acts = [];
          /* A website quotation is revised from its row: Build quote on a
             copy, linked as its revision, then sent (2026-10-26). */
          /* Two ways to show the rates (the user, 2026-10-31): Publish shows
             them on the prospect's link alone; Send quotation shows them and
             sends the quotation-ready WhatsApp, drawn once its template is on
             (`data-wa-ready`) and never for a prospect marked Do not contact,
             which quotation_send refuses (audit 2026-10-30). */
          if (maySet && awaiting(q)) {
            if (!q.no_contact_at) acts.push('<button class="btn btn-sm" data-a="send" data-wa-ready hidden type="button">Send quotation</button>');
            acts.push('<button class="btn btn-sm" data-a="publish" type="button">Publish</button>');
          }
          if (maySet && !q.removed_at && q.source === 'website' && !q._revised && st[1] !== 'is-off' && q.status !== 'not_proceeding') {
            acts.push('<button class="btn btn-sm" data-a="adjust" type="button">Adjust and send</button>');
          }
          /* Signed: the colleague checks the entries and submits them to a
             reviewer; the reviewer (or an admin) reviews (2026-10-31). The
             act stands on the row: it is what the quotation waits on. */
          if (maySet && !q.removed_at && q.signed_at && !q.reviewed_at && (!q.submitted_at || q.returned_at)) {
            acts.push('<button class="btn btn-sm" data-a="check" type="button">Submit</button>');
          }
          if (maySet && !q.removed_at && mayReview(q)) acts.push('<button class="btn btn-sm" data-a="review" type="button">Review</button>');
          if (maySet && !q.removed_at && mayOffer && offerable(q, live)) {
            acts.push('<button class="btn btn-sm" data-a="offer" type="button">Issue Letter of Offer</button>');
          }
          if (maySet && !q.removed_at) {
            items.push('<button class="kmenu-item" data-g="2" data-a="copy" type="button" role="menuitem">Duplicate</button>');
            /* Send on WhatsApp (2026-10-14): the quotation's PDF to a contact,
               drawn only once the template is on (`waOn` below). */
            if (WA() && WA().may('quotation') && q.status !== 'not_proceeding' && !awaiting(q)) {
              items.push('<button class="kmenu-item" data-g="3" data-a="wa" data-wa hidden type="button" role="menuitem">Send on WhatsApp</button>');
            }
            /* Send by email beside it (2026-10-31): optional as WhatsApp is,
               never sent by itself. */
            if (window.ADspaceDocMail && window.ADspaceDocMail.may('quotation') && q.status !== 'not_proceeding' && !awaiting(q) && !q.no_contact_at) {
              items.push('<button class="kmenu-item" data-g="3" data-a="mail" type="button" role="menuitem">Send by email</button>');
            }
            /* The quotation-ready WhatsApp again, its link button the
               prospect's own (2026-10-30): a website quotation the team has
               sent, still valid, drawn once its template is on. */
            if (q.source === 'website' && q.access_key && !awaiting(q) && !q._revised && !q.no_contact_at && q.status !== 'not_proceeding' &&
                !(q.valid_until && q.valid_until < window.ADspaceClock.today())) {
              items.push('<button class="kmenu-item" data-g="3" data-a="resend" data-wa-ready hidden type="button" role="menuitem">Resend on WhatsApp</button>');
            }
            /* A signing on paper, keyed in by the team (2026-10-31). */
            if (!q.signed_at && offerable(q, live)) items.push('<button class="kmenu-item" data-g="4" data-a="paper" type="button" role="menuitem">Mark signed</button>');
            /* The signature set aside and kept, so the client signs again;
               never once reviewed. */
            if (q.signed_at && !q.reviewed_at) items.push('<button class="kmenu-item" data-g="5" data-a="resign" type="button" role="menuitem">Request again</button>');
            if (q.source === 'website') {
              items.push(q.no_contact_at
                ? '<button class="kmenu-item" data-g="4" data-a="contact" type="button" role="menuitem">Allow contact</button>'
                : '<button class="kmenu-item" data-g="4" data-a="no_contact" type="button" role="menuitem">Do not contact</button>');
            }
            /* An accepted quotation is the client's record: no Cancel or
               Remove. */
            if (!q.reviewed_at) {
              items.push(q.status === 'not_proceeding'
                ? '<button class="kmenu-item" data-g="5" data-a="proceeding" type="button" role="menuitem">Restore</button>'
                : '<button class="kmenu-item" data-g="5" data-a="not_proceeding" type="button" role="menuitem">Cancel</button>');
              items.push('<button class="kmenu-item is-danger" data-g="6" data-a="remove" data-soft type="button" role="menuitem">Remove</button>');
            }
          }
          if (maySet && q.removed_at) items.push('<button class="kmenu-item" data-g="5" data-a="restore" type="button" role="menuitem">Restore</button>');
          return '<div class="svc-row qt-row' + (q.removed_at || st[1] === 'is-off' ? ' is-off' : '') + (acts.length ? ' has-acts' : '') + '" data-id="' + esc(q.id) + '">' +
            /* A date holds together on a phone (2026-10-20, CLI-10). */
            '<span class="svc-name qt-name"><b class="qt-ref">' + esc(q.ref) + '</b>' +
              (q.no_contact_at ? '<span class="chip qt-tag">Do not contact</span>' : '') +
              '<small>' + wholeDays(esc(metaOf(q))) + '</small><small>' + wholeDays(esc(fromOf(q))) + '</small></span>' +
            '<span class="svc-rate svc-amt qt-amt"><b>' + esc(h[0]) + '</b>' + (h[1] ? '<small>' + esc(h[1]) + '</small>' : '') + '</span>' +
            '<span class="qt-state"><span class="chip-state ' + st[1] + '">' + esc(st[0]) + '</span>' +
              (st[2] ? '<small>' + wholeDays(esc(st[2])) + '</small>' : '') + '</span>' +
            '<span class="qt-dl">' + (q.removed_at ? '' : '<button class="btn btn-sm" data-a="pdf" type="button">Download</button>') + acts.join('') + '</span>' +
            '<span class="team-act">' + (items.length ? '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' +
              DOTS + '</button><div class="kmenu" data-menu hidden>' + items.join('') + '</div>' : '') + '</span></div>';
        }).join('') + '</div>';
    }
    if (gone.length) {
      html += '<button type="button" class="btn btn-quiet btn-sm crm-removed-toggle" id="qtGone" aria-expanded="' + showRemoved + '">' +
        (showRemoved ? 'Hide ' : 'Show ') + gone.length + ' removed quotation' + (gone.length === 1 ? '' : 's') + '</button>';
      /* A small list (the user, 2026-10-31: "it should make it small list"):
         one line a removed quotation, what it was and who removed it when,
         Restore on the line and Delete in its ⋯. */
      if (showRemoved) html += '<div class="qt-gone" id="qtGoneList">' + gone.map(function (q) {
        var items = ['<button class="kmenu-item" data-g="1" data-a="pdf" type="button" role="menuitem">Download</button>'];
        if (mayDelete) items.push('<button class="kmenu-item is-danger" data-g="6" data-a="delete" type="button" role="menuitem">Delete</button>');
        return '<div class="qt-gonerow" data-id="' + esc(q.id) + '"><span class="qt-gonename"><b class="qt-ref">' + esc(q.ref) + '</b>' +
          '<small>' + wholeDays(esc(metaOf(q) + ' · Removed ' + window.ADspaceClock.date(q.removed_at) + (q.removed_by ? ' by ' + q.removed_by : ''))) + '</small></span>' +
          '<span class="qt-goneacts">' + (maySet ? '<button class="btn btn-sm" data-a="restore" type="button">Restore</button>' : '') +
          '<span class="team-act"><button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS +
          '</button><div class="kmenu" data-menu hidden>' + items.join('') + '</div></span></span></div>';
      }).join('') + '</div>';
    }
    host.innerHTML = html;
    host.hidden = false;
    wireSign();
    var b = $('qtBuild');
    if (b) b.addEventListener('click', function () { build(ctx, null, b); });
    var be = host.querySelector('.empty [data-a="build"]');
    if (be) be.addEventListener('click', function () { build(ctx, null, be); });
    if (ctx.painted) ctx.painted();
    var g = $('qtGone');
    if (g) g.addEventListener('click', function () { showRemoved = !showRemoved; paint(host, ctx, rows); });
    if (host.querySelector('[data-wa-ready]') && WA()) {
      WA().on('quote_ready').then(function (yes) {
        if (!yes) return;
        Array.prototype.forEach.call(host.querySelectorAll('[data-wa-ready]'), function (it) { it.hidden = false; });
        if (ctx.painted) ctx.painted();
      });
    }
    /* Each quotation's last email, under its reference (2026-10-31). */
    var cid = (ctx.client && ctx.client.id) || (rows[0] && rows[0].client_id);
    if (window.ADspaceDocMail && cid && list.length) {
      window.ADspaceDocMail.lines(cid).then(function (by) {
        Array.prototype.forEach.call(host.querySelectorAll('.qt-row[data-id]'), function (row) {
          var e = by[row.getAttribute('data-id')], name = row.querySelector('.qt-name');
          if (!e || !name || name.querySelector('.dm-line')) return;
          var sm = document.createElement('small');
          sm.className = 'dm-line' + (e.bad ? ' is-bad' : '');
          sm.textContent = e.line;
          name.appendChild(sm);
        });
      });
    }
    if (host.querySelector('[data-wa]')) {
      WA().on('quotation').then(function (yes) {
        if (!yes) return;
        Array.prototype.forEach.call(host.querySelectorAll('[data-wa]'), function (it) { it.hidden = false; });
      });
    }
    Array.prototype.forEach.call(host.querySelectorAll('.qt-row[data-id], .qt-gonerow[data-id]'), function (row) {
      var q = rows.filter(function (x) { return x.id === row.getAttribute('data-id'); })[0];
      var menu = row.querySelector('[data-menu]'), btn = row.querySelector('[data-a="menu"]');
      Array.prototype.forEach.call(row.querySelectorAll('.qt-dl [data-a], .qt-goneacts > [data-a="restore"]'), function (b2) {
        b2.addEventListener('click', function () { act(b2.getAttribute('data-a'), q, ctx, host, b2); });
      });
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

  /* The quotation's PDF (2026-10-31): the Quotation Cover, the quotation
     and its acceptance page. Every Download, Preview and send draws it
     through here, so each names the same people and company: the team's own
     Quotation Cover words (Settings, Document types), the colleague who
     prepared it with their position (a website quotation's, the person in
     charge), the registered company and address where Billing holds them. */
  var COVER = null, ROLES = {};
  function coverWords(ctx) {
    if (COVER) return Promise.resolve(COVER);
    return ctx.db.from('doc_types').select('title, salutation, closing, body_en').eq('id', 'quote_cover').maybeSingle()
      .then(function (r) { COVER = (r && r.data) || window.ADspaceQuotePdf.COVER; return COVER; })
      .catch(function () { return window.ADspaceQuotePdf.COVER; });
  }
  function roleOf(ctx, name) {
    if (!name) return Promise.resolve('');
    if (ROLES[name] != null) return Promise.resolve(ROLES[name]);
    return ctx.db.from('team_members').select('name, designation').eq('name', name).limit(1)
      .then(function (r) { ROLES[name] = (((r && r.data) || [])[0] || {}).designation || ''; return ROLES[name]; })
      .catch(function () { return ''; });
  }
  function drawPdf(q, ctx, extra) {
    var c = ctx.client || {};
    var by = q.made_by || (q.source === 'website' ? c.owner : '') || '';
    return Promise.all([coverWords(ctx), roleOf(ctx, by)]).then(function (got) {
      var named = q.contact && q.contact.name;
      var o = { attention: named || ctx.attention || '', attentionRole: named ? '' : (ctx.attentionRole || ''),
        to: { name: c.legal_name || c.name || q.brand, address: c.billing_address || '' },
        cover: got[0], preparedBy: { name: by, designation: got[1] }, client: c };
      var sx = signedExtra(q);
      Object.keys(sx).forEach(function (k) { o[k] = sx[k]; });
      Object.keys(extra || {}).forEach(function (k) { o[k] = extra[k]; });
      return window.ADspaceQuotePdf.draw(q, o);
    });
  }

  /* A signed quotation's PDF carries who signed, how and when, and the
     company it was signed for; once reviewed, who reviewed it
     (2026-10-31). */
  function signedExtra(q) {
    var s = q.signed, D = window.ADspaceClock.day;
    if (!q.signed_at || !s) return {};
    var co = s.company || {}, ct = s.contact || {}, sg = s.signer || {};
    var o = { signed: { name: sg.name || '', designation: sg.designation || '', day: D(q.signed_at), via: s.via || 'online',
        signature: s.signature || null, record: s.record || null, scan: s.scan || null, company: co },
      to: { name: co.legal_name || q.brand, address: co.billing_address || '' } };
    if (ct.name) { o.attention = window.ADspaceWords.person ? window.ADspaceWords.person(ct.salutation, ct.name) : ct.name; o.attentionRole = ''; }
    if (q.reviewed_at) o.reviewedBy = { name: q.reviewed_by || '', designation: q.reviewed_role || '', day: D(q.reviewed_at) };
    return o;
  }
  function meNow() { return window.ADspaceAdmin && window.ADspaceAdmin.me ? window.ADspaceAdmin.me() : null; }
  function adminNow() { var m = meNow(); return Boolean(m && (m.is_admin || m.role === 'admin')); }
  /* The reviewer chosen reviews; an admin may in their place. */
  function mayReview(q) {
    var m = meNow();
    return Boolean(q.signed_at && q.submitted_at && !q.returned_at && !q.reviewed_at && m && (m.id === q.reviewer_id || adminNow()));
  }

  var offering = {};
  function act(a, q, ctx, host, btn) {
    if (a === 'preview') { window.open('/quote/?q=' + encodeURIComponent(q.access_key) + '&preview=1', '_blank', 'noopener'); return; }
    if (a === 'link') {
      var copy = function (key) { window.ADspaceCopy.to(btn, location.origin + '/quote/?q=' + encodeURIComponent(key)); ctx.msg('qtMsg', 'Link copied.', 'ok'); };
      if (q.access_key) { copy(q.access_key); return; }
      /* A team's quotation has no link until the first copy (2026-10-31). */
      ctx.db.rpc('quotation_link', { p_id: q.id }).then(function (r) {
        var d = r.data || {};
        if (r.error || d.error || !d.key) { ctx.msg('qtMsg', said(r.error || d.error) || 'Not copied.', 'err'); return; }
        q.access_key = d.key;
        copy(d.key);
        ctx.reload();
      }).catch(function (e) { ctx.msg('qtMsg', said(e), 'err'); });
      return;
    }
    if (a === 'check') { openCheck(q, ctx, btn); return; }
    if (a === 'review') { openReview(q, ctx, btn); return; }
    if (a === 'paper') { openPaper(q, ctx, btn); return; }
    if (a === 'resign') {
      window.ADspaceConfirm.ask({ title: 'Request again?', tone: 'warn', go: 'Request again',
        body: 'The signature on ' + q.ref + ' is set aside and kept on record. The client signs again on the quotation link.' }, function () {
        ctx.db.rpc('quotation_resign', { p_id: q.id }).then(function (r) {
          var d = r.data || {};
          if (r.error || d.error) { ctx.msg('qtMsg', said(r.error || d.error), 'err'); return; }
          ctx.reload(function () { ctx.msg('qtMsg', q.ref + ' is open for signing again.', 'ok'); });
        }).catch(function (e) { ctx.msg('qtMsg', said(e), 'err'); });
      });
      return;
    }
    if (a === 'pdf' || a === 'view') {
      if (!window.ADspaceQuotePdf) return;
      var tab = a === 'view' ? window.ADspaceDocs.previewTab()
        : window.ADspaceDocs && window.ADspaceDocs.tabFor ? window.ADspaceDocs.tabFor() : null;
      drawPdf(q, ctx).then(function (blob) {
        window.ADspaceDocs.save(blob, window.ADspaceQuotePdf.fileName(q), tab);
      }).catch(function (e) {
        if (tab) try { tab.close(); } catch (x) {}
        ctx.msg('qtMsg', said(e) || 'Not drawn.', 'err');
      });
      return;
    }
    if (a === 'mail') {
      window.ADspaceDocMail.compose({ kind: 'quotation', ref: q.id, clientId: q.client_id || (ctx.client && ctx.client.id), opener: btn,
        doc: { title: 'Quotation ' + q.ref, file: function () {
          return drawPdf(q, ctx)
            .then(function (blob) { return { blob: blob, name: window.ADspaceQuotePdf.fileName(q) }; });
        } },
        onSent: function (line) { ctx.reload(function () { ctx.msg('qtMsg', line, 'ok'); }); } });
      return;
    }
    if (a === 'wa') {
      WA().compose({ purpose: 'quotation', clientId: q.client_id || (ctx.client && ctx.client.id), opener: btn,
        doc: { id: q.id, title: q.ref, file: function () {
          return drawPdf(q, ctx)
            .then(function (blob) { return { blob: blob, name: window.ADspaceQuotePdf.fileName(q) }; });
        } },
        onSent: function (d, line) { ctx.msg('qtMsg', line, 'ok'); } });
      return;
    }
    if (a === 'send') {
      /* The team sends a website quotation (2026-10-29): the prospect's link
         shows its price from now, valid from today, and the quotation-ready
         WhatsApp goes. */
      var who = (q.contact && q.contact.name) || q.brand;
      window.ADspaceConfirm.ask({ title: 'Send quotation?',
        body: q.ref + ' is shown to ' + who + ' on the quotation link and sent on WhatsApp. It is valid for ' +
          (Number(window.ADspaceMoney && window.ADspaceMoney.setting ? window.ADspaceMoney.setting('quote_valid_days') : 30) || 30) + ' days from today.',
        go: 'Send' }, function () {
        if (btn) btn.disabled = true;
        ctx.db.rpc('quotation_send', { p_id: q.id }).then(function (r) {
          var d = r.data || {};
          if (btn) btn.disabled = false;
          if (r.error || d.error) { ctx.msg('qtMsg', said(r.error || d.error), 'err'); return; }
          var line = q.ref + ' sent' + (d.whatsapp ? ' on WhatsApp' : '') + '. Valid until ' + window.ADspaceClock.date(d.valid_until) + '.';
          ctx.reload(function () { ctx.msg('qtMsg', line, 'ok'); });
        }).catch(function (e) { if (btn) btn.disabled = false; ctx.msg('qtMsg', said(e), 'err'); });
      });
      return;
    }
    if (a === 'publish') {
      /* The rates on the prospect's link with no message (2026-10-31): the
         team tells the prospect in its own chat. */
      var whom = (q.contact && q.contact.name) || q.brand;
      window.ADspaceConfirm.ask({ title: 'Publish quotation?',
        body: q.ref + ' is shown to ' + whom + ' on the quotation link. No WhatsApp message is sent. It is valid for ' +
          (Number(window.ADspaceMoney && window.ADspaceMoney.setting ? window.ADspaceMoney.setting('quote_valid_days') : 30) || 30) + ' days from today.',
        go: 'Publish' }, function () {
        if (btn) btn.disabled = true;
        ctx.db.rpc('quotation_publish', { p_id: q.id }).then(function (r) {
          var d = r.data || {};
          if (btn) btn.disabled = false;
          if (r.error || d.error) { ctx.msg('qtMsg', said(r.error || d.error), 'err'); return; }
          var line = q.ref + ' published. Valid until ' + window.ADspaceClock.date(d.valid_until) + '.';
          ctx.reload(function () { ctx.msg('qtMsg', line, 'ok'); });
        }).catch(function (e) { if (btn) btn.disabled = false; ctx.msg('qtMsg', said(e), 'err'); });
      });
      return;
    }
    if (a === 'resend') {
      var to = (q.contact && q.contact.name) || q.brand;
      var go = function (again) {
        if (btn) btn.disabled = true;
        ctx.db.rpc('quotation_resend', { p_id: q.id, p_again: !!again }).then(function (r) {
          var d = r.data || {};
          if (btn) btn.disabled = false;
          if (d.error === 'recent') {
            var rc = d.recent || {}, at = rc.at ? window.ADspaceClock.date(rc.at) + ', ' + window.ADspaceClock.clock(rc.at) : '';
            window.ADspaceConfirm.ask({ title: 'Sent recently', tone: 'warn',
              body: q.ref + ' was sent to ' + to + ' on WhatsApp' + (rc.by ? ' by ' + rc.by : ' automatically') + (at ? ' on ' + at : '') + '.',
              go: 'Send again' }, function () { go(true); });
            return;
          }
          if (r.error || d.error) { ctx.msg('qtMsg', said(r.error || d.error), 'err'); return; }
          ctx.msg('qtMsg', q.ref + ' sent again on WhatsApp.', 'ok');
        }).catch(function (e) { if (btn) btn.disabled = false; ctx.msg('qtMsg', said(e), 'err'); });
      };
      window.ADspaceConfirm.ask({ title: 'Resend on WhatsApp?',
        body: 'The Quotation ready message, with the link to ' + q.ref + ', is sent to ' + to + ' again.', go: 'Send' }, function () { go(false); });
      return;
    }
    if (a === 'copy') { build(ctx, q.selection, btn); return; }
    if (a === 'adjust') { build(ctx, q.selection, btn, q); return; }
    if (a === 'offer') {
      /* One press, one letter sheet: a second press while the lines are
         being made is let go, and the row's ⋯ turns its ring meanwhile
         (2026-10-22, QT-3, QT-8). */
      if (offering[q.id]) return;
      offering[q.id] = true;
      if (btn) btn.disabled = true;
      var done = function () { delete offering[q.id]; if (btn) btn.disabled = false; };
      ctx.db.rpc('quotation_offer', { p_id: q.id }).then(function (r) {
        var d = r.data || {};
        if (r.error || d.error) { done(); ctx.msg('qtMsg', said(r.error || d.error), 'err'); return; }
        ctx.offer(d.ids || [], done);
      }).catch(function (e) { done(); ctx.msg('qtMsg', said(e), 'err'); });
      return;
    }
    if (a === 'delete') { remove(q, ctx); return; }
    var back = { not_proceeding: 'proceeding', remove: 'restore' }[a];
    set(q, a, ctx, function () {
      if (!back) { ctx.msg('qtMsg', a === 'restore' || a === 'proceeding' ? 'Restored.' : a === 'no_contact' ? q.ref + ' marked Do not contact.' : 'Saved.', 'ok'); return; }
      ctx.undo(q.ref + (a === 'remove' ? ' removed.' : ' cancelled.'), function () {
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

  /* Delete (2026-10-31): a removed quotation, its reference typed back,
     gone for good. The database refuses one a service line, a letter or a
     revision names, and its reference is never issued again. */
  var GONE_SAID = {
    denied: 'This needs Clients: Quotations at Full Access.',
    'not-removed': 'Remove this quotation first.',
    'bad-ref': 'The reference does not match.'
  };
  function remove(q, ctx) {
    window.ADspaceConfirm.ask({
      title: 'Delete',
      body: q.ref + ' is deleted. There is no restore, and its reference is not used again.',
      go: 'Delete', tone: 'danger', wait: true,
      field: { label: 'Type the reference to confirm', placeholder: q.ref, match: q.ref,
               need: 'Type the reference to confirm.', mismatch: 'The reference does not match.' }
    }, function () {
      return ctx.db.rpc('quotation_delete', { p_id: q.id, p_ref: q.ref }).then(function (r) {
        var d = r.data || {};
        if (r.error) return said(r.error);
        if (d.error === 'lines') return 'Service lines were made from ' + q.ref + '. Delete ' + (d.count === 1 ? 'that line' : 'those ' + d.count + ' lines') + ' in Service lines first.';
        if (d.error === 'letter') return 'Letter of Offer ' + d.number + ' quotes ' + q.ref + '. A quotation a letter quotes is kept.';
        if (d.error === 'revised') return q.ref + ' was revised as ' + d.ref + ' and is kept while that quotation stands.';
        if (d.error) return GONE_SAID[d.error] || said(d.error);
        ctx.reload(function () { ctx.msg('qtMsg', q.ref + ' deleted.', 'ok'); });
        return '';
      });
    });
  }

  /* QUOTATION SIGNING (2026-10-31; the user: "Jane picks the reviewer,
     approve"). A quotation signed on its link, or keyed in from paper, is
     checked by the colleague who prepared it: the company details may be
     corrected (each correction kept, from and to), then submitted to a
     reviewer they choose. The reviewer, or an admin in their place,
     approves (Billing filled where it was empty, the lines confirmed) or
     sends it back with a note. */
  var PEN_SVG = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>';
  var CO = [['legal_name', 'Registered name'], ['company_no', 'Registration no.'], ['company_no_old', 'Old registration no.'],
    ['tin', 'TIN'], ['sst_no', 'SST no.'], ['billing_address', 'Billing address'], ['finance_email', 'Finance email']];
  var CO_NEED = { legal_name: 1, company_no: 1, billing_address: 1 };
  /* The company as the database holds it (the details form's reading). */
  function coNorm(k, v) {
    v = String(v == null ? '' : v);
    if (k === 'legal_name') return v.replace(/\s+/g, ' ').trim().toUpperCase();
    if (k === 'billing_address') return v.trim();
    if (k === 'finance_email') return v.trim().toLowerCase();
    return v.replace(/\s+/g, '').toUpperCase();
  }
  function coCheck(k, v) {
    if (!v) return CO_NEED[k] ? SAID['bad-' + k] : '';
    if (k === 'legal_name' && (v.length < 2 || v.length > 160)) return SAID['bad-legal_name'];
    if (k === 'company_no' && !/^[A-Z0-9-]{6,20}$/.test(v)) return SAID['bad-company_no'];
    if (k === 'company_no_old' && !/^[A-Z0-9-]{4,20}$/.test(v)) return SAID['bad-company_no_old'];
    if (k === 'tin' && !/^[A-Z0-9-]{6,20}$/.test(v)) return SAID['bad-tin'];
    if (k === 'sst_no' && !/^[A-Z0-9-]{6,25}$/.test(v)) return SAID['bad-sst_no'];
    if (k === 'billing_address' && (v.length < 10 || v.length > 400)) return SAID['bad-billing_address'];
    if (k === 'finance_email' && !window.ADspaceWords.emailOk(v)) return SAID['bad-finance_email'];
    return '';
  }
  function when(iso) { return iso ? window.ADspaceClock.date(iso) + ', ' + window.ADspaceClock.clock(iso) : ''; }
  function fact(label, html, cls) { return '<div><dt>' + esc(label) + '</dt><dd' + (cls ? ' class="' + cls + '"' : '') + '>' + html + '</dd></div>'; }
  /* What was signed, read first: the company (each value its pen while it is
     checked), the billing contact, the signing itself. `fix` holds the
     corrections not yet submitted. */
  function signedHtml(q, fix, edit) {
    var s = q.signed || {}, co = s.company || {}, ct = s.contact || {}, sg = s.signer || {}, rec = s.record || {};
    var was = {};
    (s.corrections || []).forEach(function (c) { if (!(c.field in was)) was[c.field] = c.from; });
    var rows = CO.map(function (f) {
      var k = f[0], v = fix && k in fix ? fix[k] : (co[k] || '');
      if (!edit && !v && !(k in was)) return '';
      var note = '';
      if (fix && k in fix) note = '<small class="qsg-was">Signed as ' + esc(co[k] || 'Not set') + '</small>';
      else if (k in was) note = '<small class="qsg-was">Signed as ' + esc(was[k] || 'Not set') + '</small>';
      return '<div><dt>' + esc(f[1]) + '</dt><dd class="mfield' + (v ? '' : ' is-empty') + (k === 'billing_address' ? ' is-pre' : '') + '">' +
        '<span class="mval" data-k="' + k + '">' + esc(v || 'Not set') + '</span>' +
        (edit ? '<button class="tl-pen" type="button" data-pen="' + k + '" aria-label="Edit ' + esc(f[1].toLowerCase()) + '">' + PEN_SVG + '</button>' : '') +
        note + '</dd></div>';
    }).join('');
    var sig = '';
    if (s.signature && s.signature.type === 'drawn') sig = '<span class="qsg-sig"><svg class="qsg-sig-svg" role="img" aria-label="Signature of ' + esc(sg.name || '') + '"><path d="' + esc(s.signature.path) + '"/></svg></span>';
    else if (s.signature && s.signature.type === 'typed') sig = '<span class="qsg-sig is-typed">' + esc(s.signature.text) + '</span>';
    var how = s.via === 'paper'
      ? fact('Signed', 'On paper') +
        fact('Keyed in by', esc((rec.by || '') + (rec.entered_at ? ' · ' + when(rec.entered_at) : ''))) +
        (s.scan && window.ADspaceWords.absUrl(s.scan) ? fact('Scan', '<a class="plink" href="' + esc(window.ADspaceWords.absUrl(s.scan)) + '" target="_blank" rel="noopener">Open scan</a>') : '')
      : fact('Signed', 'On the quotation link') +
        (rec.email ? fact('Code sent to', esc(rec.email)) : '') +
        (rec.ip ? fact('Signed from', esc(rec.ip + (rec.country ? ' · ' + rec.country : ''))) : '') +
        (rec.fingerprint ? fact('Record', '<span class="mono">' + esc(rec.fingerprint) + '</span>') : '');
    return '<section class="fsec"><h4 class="fsec-h">Company</h4><dl class="ovfacts qsg-facts">' + rows + '</dl></section>' +
      '<section class="fsec"><h4 class="fsec-h">Billing contact</h4><dl class="ovfacts qsg-facts">' +
        fact('Name', esc(window.ADspaceWords.person ? window.ADspaceWords.person(ct.salutation, ct.name) : ct.name || '')) +
        (ct.phone ? fact('Phone', esc(ct.phone)) : '') + (ct.email ? fact('Email', esc(ct.email)) : '') + '</dl></section>' +
      '<section class="fsec"><h4 class="fsec-h">Signature</h4><dl class="ovfacts qsg-facts">' +
        fact('Signed by', esc(sg.name || '') + (sg.designation ? '<small>' + esc(sg.designation) + '</small>' : ''), 'qsg-who') +
        fact('Date', esc(s.via === 'paper' ? window.ADspaceClock.date(q.signed_at) : when(q.signed_at))) +
        (sig ? fact('Signature', sig) : '') + how + '</dl></section>';
  }
  /* A drawn signature fits its own box, whatever the page it was drawn on. */
  function fitSig(host) {
    Array.prototype.forEach.call(host.querySelectorAll('.qsg-sig-svg'), function (svg) {
      try {
        var b = svg.querySelector('path').getBBox(), pad = Math.max(4, Math.max(b.width, b.height) * 0.04);
        if (b.width && b.height) svg.setAttribute('viewBox', [b.x - pad, b.y - pad, b.width + 2 * pad, b.height + 2 * pad].join(' '));
      } catch (e) {}
    });
  }
  function sheetMsg(id, text, kind) { var m = $(id); if (!m) return; m.textContent = text || ''; m.className = 'msg' + (kind ? ' ' + kind : ''); }
  function previewSigned(q, ctx, btn, msgId, fix) {
    if (!window.ADspaceQuotePdf) return;
    var tab = window.ADspaceDocs.previewTab();
    var view = q;
    if (fix && Object.keys(fix).length) {
      view = JSON.parse(JSON.stringify(q));
      Object.keys(fix).forEach(function (k) { view.signed.company[k] = fix[k] || null; });
    }
    btn.disabled = true;
    drawPdf(view, ctx).then(function (blob) {
      btn.disabled = false;
      window.ADspaceDocs.save(blob, window.ADspaceQuotePdf.fileName(q), tab);
    }).catch(function (e) {
      btn.disabled = false;
      if (tab) try { tab.close(); } catch (x) {}
      sheetMsg(msgId, said(e) || 'The PDF could not be drawn.', 'err');
    });
  }

  /* Check and submit. */
  var CK = null;
  function openCheck(q, ctx, opener) {
    if (!$('qsgCheckSheet') || !q.signed) return;
    CK = { q: q, ctx: ctx, fix: {} };
    $('qsgCheckFor').textContent = q.ref + ' · ' + q.brand;
    var back = $('qsgCheckBack');
    back.hidden = !q.returned_at;
    back.textContent = q.returned_at ? 'Sent back by ' + (q.returned_by || '') + ' on ' + when(q.returned_at) + ': ' + (q.return_note || '') : '';
    paintCheck();
    sheetMsg('qsgCheckMsg', '');
    var sel = $('qsgReviewer');
    sel.innerHTML = '<option value="">Choose a colleague</option>';
    sel.disabled = true;
    $('qsgSubmit').disabled = true;
    window.ADspaceSheet.show($('qsgCheckSheet'), { opener: opener || null, onClose: function () { CK = null; } });
    requestAnimationFrame(function () { fitSig($('qsgCheckFacts')); });
    ctx.db.rpc('quotation_reviewers', { p_id: q.id }).then(function (r) {
      if (!CK || CK.q !== q) return;
      var d = r.data || {};
      if (r.error || d.error) { sheetMsg('qsgCheckMsg', said(r.error || d.error), 'err'); return; }
      var list = d.reviewers || [];
      if (!list.length) { sheetMsg('qsgCheckMsg', 'No colleague can review it. A reviewer needs Clients: Quotations at Full Access.', 'err'); return; }
      sel.innerHTML = '<option value="">Choose a colleague</option>' + list.map(function (m) {
        return '<option value="' + esc(m.id) + '"' + (m.last ? ' selected' : '') + '>' + esc((m.code ? m.code + ' · ' : '') + m.name) + '</option>';
      }).join('');
      sel.disabled = false;
      $('qsgSubmit').disabled = false;
    }).catch(function (e) { if (CK && CK.q === q) sheetMsg('qsgCheckMsg', said(e), 'err'); });
  }
  function paintCheck() {
    var host = $('qsgCheckFacts'), q = CK.q;
    host.innerHTML = signedHtml(q, CK.fix, true);
    fitSig(host);
    Array.prototype.forEach.call(host.querySelectorAll('[data-pen]'), function (pen) {
      var k = pen.getAttribute('data-pen'), val = host.querySelector('.mval[data-k="' + k + '"]');
      var label = CO.filter(function (f) { return f[0] === k; })[0][1];
      pen.addEventListener('click', function () {
        var raw = k in CK.fix ? CK.fix[k] : ((q.signed.company || {})[k] || '');
        val.textContent = raw;
        window.ADspaceAsk.rename(val, pen, {
          value: raw, type: k === 'finance_email' ? 'email' : 'text', code: ['company_no', 'company_no_old', 'tin', 'sst_no'].indexOf(k) > -1,
          label: label, allowEmpty: !CO_NEED[k],
          check: function (v) { return coCheck(k, coNorm(k, v)) || ''; },
          save: function (v) {
            v = coNorm(k, v);
            if (v === ((q.signed.company || {})[k] || '')) delete CK.fix[k];
            else CK.fix[k] = v;
            paintCheck();
          }
        });
      });
    });
  }
  function submitCheck() {
    if (!CK) return;
    var sel = $('qsgReviewer'), q = CK.q, ctx = CK.ctx, go = $('qsgSubmit');
    if (!sel.value) { sheetMsg('qsgCheckMsg', 'Choose a reviewer.', 'err'); sel.focus(); return; }
    var who = sel.options[sel.selectedIndex].textContent.replace(/^[A-Z0-9]+ · /, '');
    var fix = Object.keys(CK.fix).length ? CK.fix : null;
    go.disabled = true;
    ctx.db.rpc('quotation_submit', { p_id: q.id, p_reviewer: sel.value, p_company: fix }).then(function (r) {
      var d = r.data || {};
      go.disabled = false;
      if (r.error || d.error) { sheetMsg('qsgCheckMsg', said(r.error || d.error), 'err'); return; }
      window.ADspaceSheet.close();
      CK = null;
      ctx.reload(function () { ctx.msg('qtMsg', q.ref + ' submitted to ' + who + '.', 'ok'); });
    }).catch(function (e) { go.disabled = false; sheetMsg('qsgCheckMsg', said(e), 'err'); });
  }

  /* Review: read only; Approve or Send back. */
  var RV = null;
  function openReview(q, ctx, opener) {
    if (!$('qsgReviewSheet') || !q.signed) return;
    RV = { q: q, ctx: ctx };
    $('qsgReviewFor').textContent = q.ref + ' · ' + q.brand;
    $('qsgReviewBy').innerHTML = '<section class="fsec"><h4 class="fsec-h">Submitted</h4><dl class="ovfacts qsg-facts">' +
      fact('By', esc(q.submitted_by || '')) + fact('On', esc(when(q.submitted_at))) +
      fact('Reviewer', esc(q.reviewer_name || '')) + '</dl></section>';
    var host = $('qsgReviewFacts');
    host.innerHTML = signedHtml(q, null, false);
    fitSig(host);
    sheetMsg('qsgReviewMsg', '');
    window.ADspaceSheet.show($('qsgReviewSheet'), { opener: opener || null, onClose: function () { RV = null; } });
    requestAnimationFrame(function () { fitSig(host); });
  }
  var BILLING_SAID = { filled: 'Billing filled from the signing.', held: 'Billing is held in Bukku and was left as Bukku holds it.', kept: 'Billing was kept as it was.' };
  function approve() {
    if (!RV) return;
    var q = RV.q, ctx = RV.ctx, me = meNow(), go = $('qsgApprove');
    var place = me && me.id !== q.reviewer_id;
    var c = ctx.client || {};
    var empty = !String(c.legal_name || '').trim() && !String(c.company_no || '').trim() && !String(c.billing_address || '').trim();
    window.ADspaceConfirm.ask({
      title: place ? 'Approve in place of ' + q.reviewer_name + '?' : 'Approve ' + q.ref + '?',
      body: (place ? q.reviewer_name + ' was asked to review it; the approval is filed under your name in their place. ' : '') +
        'Its lines become confirmed service lines' + (empty ? ', and Billing is filled from the signing.' : '. Billing is kept as it is.'),
      go: 'Approve' }, function () {
      go.disabled = true;
      ctx.db.rpc('quotation_review', { p_id: q.id, p_ok: true, p_note: null }).then(function (r) {
        var d = r.data || {};
        go.disabled = false;
        if (r.error || d.error) { sheetMsg('qsgReviewMsg', said(r.error || d.error), 'err'); return; }
        window.ADspaceSheet.close();
        RV = null;
        var line = q.ref + ' approved. ' + (d.lines || 0) + ' service line' + (d.lines === 1 ? '' : 's') + ' confirmed. ' + (BILLING_SAID[d.billing] || '') +
          (c.stage && c.stage !== 'active' ? ' Move the client to Active from the record’s stage.' : '');
        (ctx.refresh || ctx.reload)(function () { ctx.msg('qtMsg', line.trim(), 'ok'); });
      }).catch(function (e) { go.disabled = false; sheetMsg('qsgReviewMsg', said(e), 'err'); });
    });
  }
  function sendBack() {
    if (!RV) return;
    var q = RV.q, ctx = RV.ctx;
    window.ADspaceConfirm.ask({
      title: 'Send back?', go: 'Send back', wait: true,
      body: (q.submitted_by || 'The colleague who submitted it') + ' is told, and may correct the details or ask the client to sign again.',
      field: { label: 'What needs correcting', rows: 3, need: SAID['note-required'] }
    }, function (note) {
      return ctx.db.rpc('quotation_review', { p_id: q.id, p_ok: false, p_note: String(note || '').trim() }).then(function (r) {
        var d = r.data || {};
        if (r.error || d.error) return said(r.error || d.error);
        /* The question shuts first, then the sheet under it. */
        setTimeout(function () {
          window.ADspaceSheet.close();
          RV = null;
          ctx.reload(function () { ctx.msg('qtMsg', q.ref + ' sent back to ' + (q.submitted_by || 'its colleague') + '.', 'ok'); });
        }, 0);
        return '';
      });
    });
  }

  /* Mark signed: a signing on paper keyed in, so the same check and review
     follow. */
  var PP = null;
  var PAPER_FIELD = { legal_name: 'qsgPLegal', company_no: 'qsgPNo', company_no_old: 'qsgPNoOld', tin: 'qsgPTin', sst_no: 'qsgPSst',
    billing_address: 'qsgPAddress', finance_email: 'qsgPFinance', contact_salutation: 'qsgPSal', contact_name: 'qsgPName',
    contact_phone: 'qsgPPhone', contact_email: 'qsgPEmail', signer_name: 'qsgPSigner', signer_designation: 'qsgPRole', day: 'qsgPDay', scan: 'qsgPScan' };
  function openPaper(q, ctx, opener) {
    if (!$('qsgPaperSheet')) return;
    PP = { q: q, ctx: ctx };
    var c = ctx.client || {}, ct = ctx.contact || {};
    var sal = $('qsgPSal'), from = $('ctSalutation');
    if (from && sal.options.length < from.options.length) sal.innerHTML = from.innerHTML;
    $('qsgPaperFor').textContent = q.ref + ' · ' + q.brand;
    var put = function (id, v) { $(id).value = v == null ? '' : v; };
    put('qsgPLegal', c.legal_name); put('qsgPNo', c.company_no); put('qsgPNoOld', c.company_no_old); put('qsgPTin', c.tin);
    put('qsgPSst', c.sst_no); put('qsgPAddress', c.billing_address); put('qsgPFinance', c.finance_email);
    put('qsgPSal', ct.salutation || ''); put('qsgPName', ct.name); put('qsgPPhone', ct.phone); put('qsgPEmail', ct.email);
    put('qsgPSigner', ''); put('qsgPRole', ''); put('qsgPScan', '');
    var day = $('qsgPDay'), today = window.ADspaceClock.today();
    day.setAttribute('max', today);
    day.setAttribute('min', window.ADspaceClock.day(q.issued_at));
    day.value = today;
    sheetMsg('qsgPaperMsg', '');
    window.ADspaceSheet.show($('qsgPaperSheet'), { opener: opener || null, onClose: function () { PP = null; } });
  }
  function savePaper() {
    if (!PP) return;
    var q = PP.q, ctx = PP.ctx, go = $('qsgPaperSave');
    var v = function (id) { return $(id).value.trim(); };
    var bad = function (k, words) {
      sheetMsg('qsgPaperMsg', words || SAID['bad-' + k] || said(k), 'err');
      var f = $(PAPER_FIELD[k]);
      if (f) { if (window.ADspaceForm && window.ADspaceForm.reveal) window.ADspaceForm.reveal(f); f.focus(); }
    };
    var co = {};
    for (var i = 0; i < CO.length; i++) {
      var k = CO[i][0], val = coNorm(k, $(PAPER_FIELD[k]).value), w = coCheck(k, val);
      if (w) { bad(k, w); return; }
      co[k] = val || null;
    }
    if (v('qsgPName').length < 2) { bad('contact_name'); return; }
    if (v('qsgPPhone').replace(/[^0-9]/g, '').length < 8) { bad('contact_phone'); return; }
    if (!window.ADspaceWords.emailOk(v('qsgPEmail'))) { bad('contact_email'); return; }
    if (v('qsgPSigner').length < 2) { bad('signer_name'); return; }
    if (v('qsgPRole').length < 2) { bad('signer_designation'); return; }
    if (!v('qsgPDay')) { bad('day'); return; }
    var scan = v('qsgPScan');
    if (scan && !/^https:\/\//i.test(scan)) scan = /^[a-z][a-z0-9+.-]*:/i.test(scan) ? scan : 'https://' + scan;
    if (scan && !window.ADspaceWords.absUrl(scan)) { bad('scan'); return; }
    var payload = { company: co,
      contact: { salutation: v('qsgPSal') || null, name: v('qsgPName'), phone: v('qsgPPhone'), email: v('qsgPEmail').toLowerCase() },
      signer: { name: v('qsgPSigner'), designation: v('qsgPRole') }, day: v('qsgPDay'), scan: scan || null };
    go.disabled = true;
    ctx.db.rpc('quotation_paper', { p_id: q.id, p_payload: payload }).then(function (r) {
      var d = r.data || {};
      go.disabled = false;
      var e = r.error || d.error;
      if (e) { var key = String(e.message || e).replace(/^bad-/, ''); if (PAPER_FIELD[key]) bad(key); else sheetMsg('qsgPaperMsg', said(e), 'err'); return; }
      window.ADspaceSheet.close();
      PP = null;
      ctx.reload(function () { ctx.msg('qtMsg', q.ref + ' marked signed. Submit it for review.', 'ok'); });
    }).catch(function (e) { go.disabled = false; sheetMsg('qsgPaperMsg', said(e), 'err'); });
  }
  function wireSign() {
    if (wireSign.done || !$('qsgCheckSheet')) return;
    wireSign.done = true;
    $('qsgSubmit').addEventListener('click', submitCheck);
    $('qsgCheckCancel').addEventListener('click', function () { window.ADspaceSheet.close(); CK = null; });
    $('qsgCheckClose').addEventListener('click', function () { $('qsgCheckCancel').click(); });
    $('qsgCheckPdf').addEventListener('click', function () { if (CK) previewSigned(CK.q, CK.ctx, this, 'qsgCheckMsg', CK.fix); });
    $('qsgApprove').addEventListener('click', approve);
    $('qsgSendBack').addEventListener('click', sendBack);
    $('qsgReviewCancel').addEventListener('click', function () { window.ADspaceSheet.close(); RV = null; });
    $('qsgReviewClose').addEventListener('click', function () { $('qsgReviewCancel').click(); });
    $('qsgReviewPdf').addEventListener('click', function () { if (RV) previewSigned(RV.q, RV.ctx, this, 'qsgReviewMsg'); });
    $('qsgPaperSave').addEventListener('click', savePaper);
    $('qsgPaperCancel').addEventListener('click', function () { window.ADspaceSheet.close(); PP = null; });
    $('qsgPaperClose').addEventListener('click', function () { $('qsgPaperCancel').click(); });
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

  /* `revises`: a website quotation this one revises (Adjust and send): once
     made it is linked to it and the WhatsApp composer opens on it. */
  function build(ctx, sel, opener, revises) {
    sel = sel || {};
    /* `edits`: a line's quantity, rate and months the team typed, by the
       line's key (2026-10-15, the user: "fully customised for the rates qty
       and months"); priced and kept by the database as typed. */
    B = { ctx: ctx, seq: 0, idem: null, plan: sel.plan || null, edits: JSON.parse(JSON.stringify(sel.edits || {})), revises: revises || null, opener: opener };
    /* The tax codes a line may take (2026-10-22), drawn once read. */
    MON.taxCodes().then(function (list) {
      if (!B) return;
      B.codes = list;
      if (B.priced && list.some(function (c) { return c.active; })) $('qbLines').innerHTML = table(B.priced);
    });
    $('qbMsg').textContent = ''; $('qbMsg').className = 'msg';
    $('qbFor').textContent = (ctx.client.client_code ? ctx.client.client_code + ' · ' : '') + ctx.client.name;
    $('qbLines').innerHTML = ''; $('qbSum').textContent = '';
    FX = MON.curOf(ctx.client) === 'SG' ? Number(MON.setting('fx_sgd')) || 0 : null;
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
      window.ADspaceSheet.show($('qbBox'), { opener: opener || null, onClose: function () { B = null; } });
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
        '<small>' + p.spec.contents + ' content pieces: ' + mixWords(p.spec.mix || [], true) + '</small>' +
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
    /* A changed selection is a new quotation: its own key (audit 15, 2026-10-19). */
    if (B) B.idem = null;
    timer = setTimeout(function () {
      if (!B) return;
      var seq = ++B.seq;
      B.sel = selection();
      B.priced = null;
      $('qbSave').disabled = true;
      $('qbPreview').disabled = true;
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
        $('qbSum').textContent = sumOf(d) + (FX == null ? MON.approx(mainOf(d), B.ctx.client) : '');
        $('qbSave').disabled = false;
        $('qbPreview').disabled = false;
      }).catch(function (e) { if (B && seq === B.seq) $('qbLines').innerHTML = '<p class="ovnone">' + esc(said(e)) + '</p>'; });
    }, 200);
  }
  /* The figure the person is choosing towards, kept in sight in the foot
     while the lines and totals sit at the sheet's end (2026-10-15). */
  /* The figure the foot leads with, for its approx. S$ beside it. */
  function mainOf(d) {
    var t = (d && d.totals) || {}, own = t.month && ownMonths(d && d.lines, t);
    return t.month ? (own ? firstIncl(t) : t.month.incl) : t.once ? t.once.incl : null;
  }
  function sumOf(d) {
    var t = (d && d.totals) || {}, out = [];
    var own = t.month && ownMonths(d && d.lines, t);
    if (t.month) out.push(CUR + ' ' + acct(own ? firstIncl(t) : t.month.incl) + (own ? ' first month' : ' monthly'));
    if (t.once && !own) out.push(CUR + ' ' + acct(t.once.incl) + ' one-off');
    return out.length ? out.join(' · ') + (MON.sstOf(d.lines, t.sst_pct).on ? ' incl. SST' : '') : '';
  }
  /* The lines and the totals as the quotation will keep them. */
  function table(d) {
    var t = d.totals || {}, rows = d.lines || [];
    /* The head holds a cell for the Tax cell where the lines carry one, so
       its cells stand over the lines' (2026-10-31). */
    var hasTax = (B && B.codes || []).some(function (c) { return c.active; });
    var out = '<div class="crm-table qb-table"><div class="crm-head svc-row qb-row"><span class="qb-name">Line</span>' + (hasTax ? '<span class="qb-taxc"></span>' : '') + '<span class="svc-rate qb-qty">Qty</span>' +
      '<span class="svc-rate qb-rate">Rate (' + CUR + ')</span><span class="svc-rate qb-mo">Months</span><span class="svc-rate qb-amt">Subtotal (' + CUR + ')</span></div>' +
      rows.map(function (l) {
        /* Quantity, rate and months are typed where they are read; a line
           quoted off the card names the card's rate under it. */
        var sub = [];
        if (l.list_rate != null) sub.push('Rate card ' + CUR + ' ' + rm(l.list_rate));
        /* The line's tax code (2026-10-22): the client's SST, or one the team
           bills with, chosen where it is read; drawn while any is offered.
           The client's own reads as the rate alone (SST 8%), the codes by
           their code, so on a phone it shares the line with Qty, Rate and
           Months (2026-10-31). */
        var codes = (B && B.codes || []).filter(function (c) { return c.active; });
        var cur = (B && B.edits[l.key] && B.edits[l.key].tax) || l.tax_code || '';
        var tax = codes.length ? '<select class="select select-sm qb-tax" data-nofind data-key="' + esc(l.key || '') + '" aria-label="' + esc('Tax, ' + l.label) + '">' +
          '<option value="">' + esc(MON.sstApplies(t.sst_pct) ? 'SST ' + t.sst_pct + '%' : 'No SST') + '</option>' +
          codes.map(function (c) { return '<option value="' + esc(c.code) + '"' + (c.code === cur ? ' selected' : '') + '>' + esc(MON.taxCodeWord(c)) + '</option>'; }).join('') +
          '</select>' : '';
        var box = function (what, v, cls, mode, label) {
          return '<input class="input input-sm qb-val ' + cls + '" type="text" inputmode="' + mode + '" data-noenter data-nodraft data-key="' +
            esc(l.key || '') + '" data-what="' + what + '" value="' + esc(v) + '" aria-label="' + esc(label + ', ' + l.label) + '">';
        };
        return '<div class="svc-row qb-row"><span class="svc-name qb-name">' + esc(l.label) + (sub.length ? '<small>' + esc(sub.join(' · ')) + '</small>' : '') + '</span>' +
          (tax ? '<span class="qb-taxc"><span class="qb-lab">Tax</span>' + tax + '</span>' : '') +
          '<span class="svc-rate qb-qty"><span class="qb-lab">Qty</span>' + box('qty', l.qty, 'qb-qtyval', 'numeric', 'Quantity') + '</span>' +
          '<span class="svc-rate qb-rate"><span class="qb-lab">Rate (' + CUR + ')</span>' + box('rate', rm(l.rate), 'qb-rateval', 'decimal', 'Rate (' + CUR + ')') + '</span>' +
          '<span class="svc-rate qb-mo"><span class="qb-lab">Months</span>' + (l.basis === 'month' ? box('months', l.months || (d.totals || {}).term, 'qb-moval', 'numeric', 'Months') :
            '<span class="qb-once">One-off</span>') + '</span>' +
          '<span class="svc-rate qb-amt">' + esc(rm(l.amount)) + '</span></div>';
      }).join('') + '</div>';
    /* SST said as the Letter of Offer says it (ADspaceMoney.sstApplies);
       the rows are ADspaceMoney.quoteRows', one copy (QT-4). */
    var taxed = MON.sstOf(rows, t.sst_pct), sstOn = taxed.on, incl = sstOn ? ' incl. SST' : '';
    var WORD = { monthSub: 'Monthly subtotal', onceSub: 'One-off subtotal', firstExcl: 'First month excl. SST', monthExcl: 'Monthly excl. SST',
      sst: taxed.word, first: 'First month' + incl, monthly: 'Monthly' + incl, oneOff: sstOn ? 'One-off incl. SST' : 'One-off total',
      term: t.term + '-month ' + (t.term_pct < 0 ? 'commitment (' + Math.abs(t.term_pct) + '%)' : 'term (' + t.term_pct + '%)') };
    var tot = MON.quoteRows(t, rows, sstOn).map(function (x) { return [WORD[x[0]], (x[2] ? CUR + ' ' : '') + acct(x[1]), x[2]]; });
    out += '<dl class="qb-tot">' + tot.map(function (x) {
      return '<div' + (x[2] ? ' class="is-total"' : '') + '><dt>' + esc(x[0]) + '</dt><dd>' + esc(x[1]) + '</dd></div>';
    }).join('') + '</dl>';
    var notes = [];
    if (t.budget > 0) notes.push('Advertising budget of up to ' + CUR + ' ' + whole(t.budget) + ' per month is billed separately.');
    if ((d.on_request || []).length) notes.push('On request: ' + d.on_request.map(function (x) { return x === 'budget' ? 'advertising budget above ' + CUR + ' ' + whole(topBudget()) : x; }).join(', ') + '.');
    if (notes.length) out += '<p class="qb-note">' + esc(notes.join(' ')) + '</p>';
    return out;
  }

  /* The quotation just made is marked where it lands and its Download
     takes focus, the mark leaving after the Undo bar's time (2026-10-22,
     QT-2). */
  var NEW_MS = 8000;
  function markNew(ref) {
    var row = Array.prototype.filter.call(document.querySelectorAll('.qt-row[data-id]'), function (x) {
      var r = x.querySelector('.qt-ref'); return r && r.textContent === ref;
    })[0];
    if (!row) return;
    row.classList.add('is-new');
    var dl = row.querySelector('.qt-dl [data-a="pdf"]');
    if (dl) dl.focus({ preventScroll: false });
    setTimeout(function () { row.classList.remove('is-new'); }, NEW_MS);
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
      var tx = e.target.closest('.qb-tax');
      if (tx && B) {
        var k0 = tx.getAttribute('data-key'), e0 = B.edits[k0] || {};
        if (tx.value) e0.tax = tx.value; else delete e0.tax;
        if (Object.keys(e0).length) B.edits[k0] = e0; else delete B.edits[k0];
        preview();
        return;
      }
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
    /* Preview PDF (2026-10-31; the user: "preview pdf … before sending"):
       the quotation as it is priced now, drawn under DRAFT with the
       reference PREVIEW; nothing is made and no number is spent. */
    $('qbPreview').addEventListener('click', function () {
      if (!B || !B.priced || !window.ADspaceQuotePdf) return;
      var d = B.priced, ctx = B.ctx, btn = this;
      var today = window.ADspaceClock.today();
      var days = Number(window.ADspaceMoney && window.ADspaceMoney.setting ? window.ADspaceMoney.setting('quote_valid_days') : 30) || 30;
      var me = window.ADspaceAdmin && window.ADspaceAdmin.me ? window.ADspaceAdmin.me() : null;
      var q = { ref: 'PREVIEW', brand: ctx.client.name, issued_at: today, valid_until: window.ADspaceClock.addDays(today, days),
        made_by: (me && me.name) || '',
        version: d.version, lines: d.lines, totals: d.totals, selection: B.sel };
      var tab = window.ADspaceDocs.previewTab();
      btn.disabled = true;
      drawPdf(q, ctx, { draft: true }).then(function (blob) {
        btn.disabled = false;
        window.ADspaceDocs.save(blob, 'Preview ' + window.ADspaceQuotePdf.fileName(q), tab);
      }).catch(function (e) {
        btn.disabled = false;
        if (tab) try { tab.close(); } catch (x) {}
        $('qbMsg').textContent = said(e) || 'The preview could not be drawn.'; $('qbMsg').className = 'msg err';
      });
    });
    $('qbSave').addEventListener('click', function () {
      if (!B || !B.priced) return;
      var go = this;
      B.idem = B.idem || (window.ADspaceDocs && window.ADspaceDocs.idemKey ? window.ADspaceDocs.idemKey() : (window.crypto && window.crypto.randomUUID ? window.crypto.randomUUID() : String(Date.now()) + Math.random().toString(36).slice(2)));
      go.disabled = true;
      B.ctx.db.rpc('quotation_create', { p_client: B.ctx.client.id, p_sel: B.sel, p_idem: B.idem }).then(function (r) {
        var d = r.data || {};
        go.disabled = false;
        if (r.error || d.error) { $('qbMsg').textContent = said(r.error || d.error); $('qbMsg').className = 'msg err'; return; }
        var ctx = B.ctx, revises = B.revises, opener = B.opener;
        window.ADspaceSheet.close();
        B = null;
        if (!revises) { ctx.reload(function () { ctx.msg('qtMsg', d.ref + ' made.', 'ok'); markNew(d.ref); }); return; }
        ctx.db.rpc('quotation_replace', { p_new: d.id, p_old: revises.id }).then(function (r2) {
          var e2 = (r2 && r2.error) || (r2 && r2.data && r2.data.error);
          ctx.reload(function (rows) {
            if (e2) { ctx.msg('qtMsg', d.ref + ' made, but not linked to ' + revises.ref + ': ' + said(e2), 'err'); return; }
            ctx.msg('qtMsg', d.ref + ' revises ' + revises.ref + '.', 'ok'); markNew(d.ref);
            var made = (rows || []).filter(function (x) { return x.id === d.id; })[0];
            if (made && WA() && WA().may('quotation')) WA().on('quotation').then(function (yes) { if (yes) act('wa', made, ctx, opener); });
          });
        }).catch(function (e) { ctx.reload(function () { ctx.msg('qtMsg', said(e), 'err'); }); });
      }).catch(function (e) { go.disabled = false; $('qbMsg').textContent = said(e); $('qbMsg').className = 'msg err'; });
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', wire); else wire();

  window.ADspaceQuotes = { load: load, paint: paint, overview: overview, build: build, stateOf: stateOf, headline: headline, offerable: offerable };
})();
