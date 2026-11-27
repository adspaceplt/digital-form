/* ADspace Digital Portal — a client's quotations (2026-10-14).
 *
 * A quotation is made from a selection and priced by the database alone
 * (`quote_preview` while it is ticked, `quotation_create` to keep it), from
 * the version of the rate card that is live, so the console, the website and
 * the PDF never disagree. It is kept as sent and never edited: Make a copy
 * prices the same selection again, and a client may hold several. The
 * client signs it on its link, the colleague who prepared it submits it to a
 * reviewer, and the reviewer's approval confirms its lines (QUOTATION
 * SIGNING, 2026-10-31); no Letter of Offer is issued from it.
 *
 * crm.js hands each call its context: { client, db, may(part, level),
 * esc, msg(id, text, kind), services, live (service id to letter number),
 * reload(done), refresh(done), contact, painted, undo(text, fn, host) }.
 */
(function () {
  'use strict';
  var MON = window.ADspaceMoney;
  var $ = function (id) { return document.getElementById(id); };
  function WA() { return window.ADspaceWhatsApp; }
  var esc = window.ADspaceWords.esc;
  var wholeDays = function (h) { return String(h).replace(/\b(\d{1,2}) ([A-Z][a-z]{2,3}) (\d{4})\b/g, '$1\u00a0$2\u00a0$3'); };
  var DOTS = window.ADspaceIcons.glyph('more');
  var SAID = {
    'send-off': window.ADspaceWords.line.whatsappSendOff,
    denied: 'You do not have permission to change quotations. Please ask an admin.', 'client-scope': 'You do not have access to this client. Please ask an admin.',
    'no-card': 'No Rate Card version is live. Publish one in Services.', 'bad-plan': 'That plan is not on the live Rate Card.',
    'no-platform': 'Choose at least one platform.',
    empty: 'Choose a plan, a package, an advertising budget or an item.', 'nothing-priced': 'Add an item with a listed rate. Items quoted on request cannot form a quotation on their own.', revised: 'This quotation has been revised. Send the revised quotation instead.', 'bad-extra': 'Enter whole numbers for additional content pieces.',
    'bad-once': 'Enter whole numbers for one-time items.', 'not-found': 'This quotation no longer exists.',
    'not-proceeding': 'This quotation is cancelled. Restore it first.',
    'not-confirmed': 'This quotation is still a draft. Confirm it first.', website: 'This quotation came from a website request. Use Send quotation to confirm it.', 'bad-budget': 'Choose an advertising budget.',
    'bad-edit': 'Enter a whole quantity from 1, a rate of up to two decimal places, and 1 to 36 months.',
    'bad-brands': 'Enter each brand\'s name.',
    'over-term': 'An item cannot run longer than the term. Set its months to the term or fewer.',
    'bad-card': 'That Rate Card version is no longer available. Choose another.',
    'bad-tax': 'That tax code is no longer offered. Choose another.',
    'bad-date': window.ADspaceWords.line.docDate,
    'bad-ads': 'Enter each platform\'s budget, and the months from 1 to 36.',
    'bad-pay': 'Choose the payment terms.',
    'bad-valid': 'Choose how many days the quotation is valid for.',
    'bad-period': 'Tick or untick Show totals for the whole period, then try again.',
    'bad-title': 'Enter a title of up to 120 characters.', 'bad-order': 'The order of the items could not be read. Refresh the page.',
    'bad-custom': 'Enter each custom item\'s name, quantity and rate, and its months from 1 to 36.',
    'bad-package': 'Enter the package name, its price and at least one Rate Card service, each with a quantity.',
    'bad-renewal': 'A service line to renew is no longer confirmed. Remove it and choose Renew service lines again.',
    'bad-entity': 'That billing entity no longer bills this client. Choose another under Bill to.',
    'bad-terms': window.ADspaceWords.line.terms,
    expired: 'This quotation has expired. Use Build quote to quote again.',
    sent: 'Not saved. This quotation was sent meanwhile. Refresh the page to revise it.',
    removed: 'This quotation has been removed. Restore it first.',
    lines: 'Not saved. Service lines were created from this quotation. Refresh the page to revise it.',
    letter: 'Not saved. A Letter of Offer was issued from this quotation. Refresh the page to revise it.',
    'not-sent': 'Send the quotation first.', 'no-contact': 'This prospect is marked Do not contact. Choose Allow contact first.',
    'wa-off': 'The Quotation ready WhatsApp template is off. Turn it on in Settings, Messages, WhatsApp templates.',
    'no-number': 'This prospect has no WhatsApp number. Add one in Contacts first.',
    'wa-limit': 'Today\'s WhatsApp limit for quotations from the Quotation portal has been reached. Send the quotation tomorrow, or raise the limit in Settings, Messages, Quotation portal on WhatsApp.',
    'no-fx': window.ADspaceWords.line.fxUnset,
    /* Signing, submitting and reviewing (QUOTATION SIGNING, 2026-10-31). */
    'not-signed': 'This quotation has not been signed. Mark it signed, or send the client the link to sign.', signed: 'This quotation has already been signed. Refresh the page.',
    reviewed: 'This quotation has already been reviewed. Refresh the page.',
    'in-review': 'This quotation is already with its reviewer. Refresh the page.',
    'pick-company': 'Choose Keep or Use for each company detail that differs from the client record.',
    'bad-reviewer': 'Choose a colleague with Clients: Quotations at Full control.', own: 'Choose a reviewer other than yourself.',
    'not-submitted': 'This quotation is not waiting for review. Refresh the page.',
    'not-reviewer': 'Only the chosen reviewer or an admin can approve this quotation.',
    'note-required': 'Enter the corrections.',
    'billing-access': 'Approving fills in Billing, which you do not have permission to change. Please ask the chosen reviewer or an admin.',
    'bad-day': 'Choose the day it was signed, from the day it was issued to today.',
    'bad-scan': 'Enter the scan as a web address starting https://.',
    'bad-legal_name': 'Enter the Registered Company Name.', 'bad-company_no': 'Enter the Business Registration Number: 6 to 20 letters or digits.',
    'bad-company_no_old': 'Enter the Old Registration Number: 4 to 20 letters or digits.',
    'bad-tin': 'Enter the Tax Identification Number (TIN): 6 to 20 letters or digits.', 'bad-sst_no': 'Enter the SST Registration Number: 6 to 25 letters or digits.',
    'bad-billing_address': 'Enter the billing address in full.', 'bad-finance_email': 'Enter a valid email address.',
    'bad-contact_salutation': 'Choose a salutation from the list.', 'bad-contact_name': 'Enter the billing contact\'s name.',
    'bad-contact_phone': 'Enter the billing contact\'s phone number.', 'bad-contact_email': 'Enter a valid email address.',
    'bad-signer_name': 'Enter the name of the person who signed.', 'bad-signer_designation': 'Enter their designation.'
  };
  function said(e) {
    if (!e) return '';
    var m = String(e.message || e);
    if (/could not find|does not exist|schema cache/i.test(m)) return 'This feature is not available yet. Please contact an admin.';
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
    if (isDraft(q)) return ['Draft', 'is-off'];
    /* Withdrawn after signing (QUOTATION WAYS OUT, 2026-11-17): kept, its
       sealed copy too, never deleted. */
    if (q.withdrawn_at) return ['Withdrawn', 'is-off', 'From ' + window.ADspaceClock.date(q.withdrawn_on).replace(/ \d{4}$/, '')];
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
    if (q.status === 'not_proceeding') return q.declined_at ? ['Declined', 'is-off', 'By the client']
      : q.not_quoted ? ['Not quoted', 'is-off', NOT_QUOTED[q.not_quoted] || ''] : ['Cancelled', 'is-off'];
    /* A later quotation made from this one revises it; the prospect's link
       shows that one (2026-10-26). */
    if (q._revised) return ['Revised', 'is-off', 'By ' + q._revised];
    /* A website quotation waits for the team before the prospect sees the
       price (2026-10-29). */
    /* The prospect asked for changes on the sent quotation's link
       (QUOTATION CHANGES REQUESTED, 2026-11-25): the team owes the
       revision by its reply day. */
    if (q.change_requested_at) return ['Changes requested', 'is-warn', q.reply_due ? 'Send by ' + window.ADspaceClock.date(window.ADspaceClock.day(q.reply_due)).replace(/ \d{4}$/, '') : ''];
    /* Details asked of the prospect (QUOTE DETAILS ASKED, 2026-11-27), worked
       out on every load: owed by Reply by, red once it passes, Not quoted ·
       No response once the close days pass too; Details received owes the
       quotation again by its Send by. */
    var ds = awaiting(q) ? detailsState(q) : 'none';
    if (ds === 'closed') return ['Not quoted', 'is-off', 'No response'];
    if (ds === 'asked' || ds === 'late') return ['Waiting for details', ds === 'late' ? 'is-danger' : 'is-warn', 'Reply by ' + shortDay(q.details_due)];
    if (ds === 'received') return ['Details received', 'is-warn', q.reply_due ? 'Send by ' + shortDay(q.reply_due) : ''];
    if (awaiting(q)) return ['Awaiting review', 'is-warn', q.reply_due ? 'Send by ' + window.ADspaceClock.date(window.ADspaceClock.day(q.reply_due)).replace(/ \d{4}$/, '') : ''];
    var today = window.ADspaceClock.today();
    if (q.valid_until < today) return ['Expired', 'is-off'];
    if (q.status === 'requested') return ['Letter of Offer requested', 'is-warn'];
    if (q.proceed_at) return ['Ready to proceed', 'is-warn', 'Contact by ' + window.ADspaceClock.date(window.ADspaceClock.day(q.proceed_due)).replace(/ \d{4}$/, '')];
    return ['Valid until ' + window.ADspaceClock.date(q.valid_until).replace(/ \d{4}$/, ''), 'is-live'];
  }
  /* QUOTATION EDITED UNTIL SENT (2026-11-06; the user: "Quotation is a
     serious one so it must be accurate"): a quotation is edited in place,
     its number and link kept, until the portal sends it out (released, its
     link given, a WhatsApp or an email); after that Edit makes its next
     revision. Download never locks it. */
  function sentOut(q) { return Boolean(q.sent_out_at || q.released_at); }
  /* A team's quotation is a draft until a colleague confirms it (the user,
     2026-11-26): it reads ADP/QT{YYMM}-DRAFT, offers Preview PDF, Edit,
     Confirm quotation and Remove, and goes nowhere until then; the
     database refuses every send (`not-confirmed`). A website request is
     confirmed by Send quotation. Its reference as people read it. */
  function isDraft(q) { return !!q && !q.confirmed_at && q.source !== 'website'; }
  function refOf(q) { return isDraft(q) ? dref(q.ref) : q.ref; }
  function dref(r) { return String(r || '').replace(/-DRAFT-[A-Z]+$/, '-DRAFT'); }
  function editable(q) {
    return !q.removed_at && !q.signed_at && !q.reviewed_at && q.status !== 'not_proceeding' && !q._revised;
  }
  var NOT_QUOTED = { incomplete: 'Incomplete details', fit: 'Not a fit', duplicate: 'Duplicate', spam: 'Spam' };
  function shortDay(ts) { return window.ADspaceClock.date(window.ADspaceClock.day(ts)).replace(/ \d{4}$/, ''); }
  function detailsState(q) {
    if (!q.details_asked_at) return 'none';
    if (q.details_at) return 'received';
    var due = new Date(q.details_due).getTime(), now = Date.now();
    var close = Number(MON.setting('quote_details_close_days', window.ADspaceClock.day(q.details_due))) || 7;
    if (now > due + close * 864e5) return 'closed';
    return now > due ? 'late' : 'asked';
  }
  /* A website request the team may still ask about or decline: unsent and
     open (never once Not quoted, worked out or chosen). */
  function askable(q) { return awaiting(q) && detailsState(q) !== 'closed'; }
  function awaiting(q) { return q.source === 'website' && !q.released_at && !q._revised && !q.removed_at && q.status !== 'not_proceeding'; }
  /* A quotation that can still become a Letter of Offer: valid, or the
     client has asked for the letter (2026-10-22, QT-M1). */
  function offerable(q, live) {
    if (q.removed_at) return false;
    var st = stateOf(q, live);
    return st[1] === 'is-live' || st[0] === 'Letter of Offer requested' || st[0] === 'Ready to proceed';
  }
  function monthly(q) { var m = q.totals && q.totals.month; return m ? m.incl : null; }
  /* A draft's row: Preview PDF and Confirm quotation on it, Edit and Remove
     in its ⋯ (2026-11-26). */
  function draftRow(q, st, h, maySet) {
    var items = maySet ? ['<button class="kmenu-item" data-g="2" data-a="edit" type="button" role="menuitem">Edit</button>',
      '<button class="kmenu-item is-danger" data-g="6" data-a="remove" data-soft type="button" role="menuitem">Remove</button>'] : [];
    return '<div class="svc-row qt-row has-acts" data-id="' + esc(q.id) + '">' +
      '<span class="svc-name qt-name"><b class="qt-ref">' + window.ADspaceCopy.ref(refOf(q)) + '</b>' +
        '<small>' + wholeDays(esc(metaOf(q))) + '</small><small>' + wholeDays(esc(fromOf(q))) + '</small></span>' +
      '<span class="svc-rate svc-amt qt-amt"><b>' + esc(h[0]) + '</b>' + (h[1] ? '<small>' + esc(h[1]) + '</small>' : '') + '</span>' +
      '<span class="qt-state"><span class="chip-state ' + st[1] + '">' + esc(st[0]) + '</span></span>' +
      '<span class="qt-dl"><button class="btn btn-sm" data-a="view" type="button">Preview PDF</button>' +
        (maySet ? '<button class="btn btn-sm btn-primary" data-a="confirm" type="button">Confirm quotation</button>' : '') + '</span>' +
      '<span class="team-act">' + (items.length ? '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' +
        DOTS + '</button><div class="kmenu" data-menu hidden>' + items.join('') + '</div>' : '') + '</span></div>';
  }
  /* A monthly line running months of its own makes the month's figures the
     first month's, named so (the user, 2026-10-18), as the Letter of Offer
     and the quotation's PDF name them. */
  function ownMonths(lines, t) {
    return (lines || []).some(function (l) { return l.basis === 'month' && l.months && Number(l.months) !== Number((t || {}).term); });
  }
  /* The first month holds the one-time items too (the user, 2026-10-18). */
  function sum2(a, b) { return MON.cents(Number(a || 0) + Number(b || 0)); }
  function firstIncl(t) { return sum2(t.month.incl, t.once && t.once.incl); }
  function headline(q) {
    var m = monthly(q);
    var incl = MON.sstOf(q.lines, (q.totals || {}).sst_pct).on ? ' incl. SST' : '';
    if (m != null) return ownMonths(q.lines, q.totals) ? [curOf(q) + ' ' + rm(firstIncl(q.totals)), 'First month' + incl]
      : [curOf(q) + ' ' + rm(m), 'Monthly' + incl];
    var o = q.totals && q.totals.once;
    return o ? [curOf(q) + ' ' + rm(o.incl), incl ? 'One-time' + incl : 'One-time total'] : ['—', ''];
  }
  var COLS = 'id, ref, client_id, brand, version, version_id, selection, lines, totals, status, source, issued_at, ' +
    'valid_until, made_by, contact, access_key, requested_at, removed_at, removed_by, proceed_at, proceed_due, proceed_start, proceed_decider, replaces, no_contact_at, released_at, reply_due, ' +
    'signed_at, signed, submitted_at, submitted_by, reviewer_id, reviewer_name, reviewed_at, reviewed_by, reviewed_role, returned_at, return_note, returned_by, sign_history, sent_out_at, ' +
    'sealed_at, seal_sha, seal_pages_sha, sealed_by, signed_words, declined_at, decline_reason, withdrawn_at, withdrawn_on, withdrawn_reason, withdrawn_by, commence_on, change_request, change_requested_at, ' +
    'confirmed_at, confirmed_by, revises, request_ref, ' +
    'details_ask, details_asked_at, details_asked_by, details_due, details_at, details, not_quoted, match, match_taken';
  /* Two short lines (2026-10-26, the user: "too many info"): what it is, then
     where it came from and when. */
  function metaOf(q) {
    var t = q.totals || {};
    var bits = [];
    var plans = (q.lines || []).filter(function (l) { return l.kind === 'plan'; });
    /* Several brands (2026-11-24): their count, then each plan. */
    if (Array.isArray(t.brands) && t.brands.length > 1) bits.push(t.brands.length + ' brands');
    if (plans.length) bits.push(plans.map(function (p) { return p.label.replace(/^Social Media Services · /, '').replace(/ \(.*\)$/, ''); }).join(', '));
    if (t.month) bits.push(t.term + ' months');
    if (!bits.length) bits.push('One-time');
    return bits.join(' · ');
  }
  function fromOf(q) {
    /* The Rate Card version it was priced on, held from the press that made it (QUOTATION PREFLIGHT, 2026-11-25). */
    return (q.source === 'website' ? 'Website' : q.made_by || 'The team') + ' · ' + window.ADspaceClock.date(q.issued_at) +
      (q.version ? ' · Rate Card v.' + q.version : '') + (q._revises ? ' · revises ' + q._revises : '');
  }
  /* The day the client asked to start, kept on the quotation it asked on
     (START DATE ON THE QUOTATION, 2026-11-21); a revision reads the day of
     the quotation it revises, since the client asked it once. */
  function askedStart(q) { return (q && (q._start || q.commence_on)) || null; }
  function startNote(q) {
    var d = askedStart(q);
    return d ? 'The client asked for ' + window.ADspaceClock.date(d) + ' on this quotation. Service lines with their own start date keep it.'
      : 'Service lines with their own start date keep it.';
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
        rows.forEach(function (q) {
          var at = q, seen = {};
          while (at && !at.commence_on && at.replaces && !seen[at.id]) {
            seen[at.id] = true;
            at = rows.filter(function (x) { return x.id === at.replaces; })[0];
          }
          q._start = at && at.commence_on ? at.commence_on : null;
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
    /* The part is a card, its count beside its title and its add act quiet
       until it is the record's next step (the user, 2026-11-13, A to D). */
    var html = '<div class="viewhead qt-head"><span class="headmark"><h2>Quotations</h2>' +
      (shown.length ? '<span class="tab-n part-n">' + shown.length + '</span>' : '') + '</span>' +
      (maySet ? '<button class="btn btn-quiet btn-sm" id="qtBuild" type="button">' + PLUS + 'Build quote</button>' : '') + '</div>' +
      '<div class="msg" id="qtMsg"></div>';
    /* Settings, Messages: Website quotations at 0 (SWITCHED-OFF ACTS,
       release B): a website quotation waiting for the team cannot go on
       WhatsApp, so the part says so once, and Send quotation stays drawn,
       disabled with the same words (`data-gate="whatsapp quotewa"`). */
    var A = window.ADspaceAdmin;
    if (maySet && A && A.gateState && !A.gateState('quotewa').on && shown.some(awaiting)) {
      html += '<p class="msg warn" id="qtWaOff">' + esc(window.ADspaceWords.line.quoteWaOffAll) + '</p>';
    }
    /* What needs the team first, then what stands, then what is settled,
       then what is over (Expired, Revised, Cancelled); each newest first
       as read (2026-11-03). */
    var RANK = { 'is-danger': 0, 'is-warn': 0, 'is-live': 1, 'is-ok': 2, 'is-off': 3 };
    var list = shown.map(function (q, i) { return [RANK[stateOf(q, live)[1]], i, q]; })
      .sort(function (a, b) { return (a[0] - b[0]) || (a[1] - b[1]); }).map(function (x) { return x[2]; });
    /* An empty list is words alone: Build quote is the heading's, as every
       record pane's act is (2026-11-03). */
    if (!list.length) html += '<div class="empty">No quotations.</div>';
    else {
      html += '<div class="crm-table qt-table"><div class="crm-head svc-row qt-row"><span>Quotation</span>' +
        '<span class="svc-rate">Amount</span><span>Status</span><span></span><span></span></div>' +
        list.map(function (q) {
          var st = stateOf(q, live), h = headline(q);
          if (isDraft(q)) return draftRow(q, st, h, maySet);
          var items = [];
          /* A website request the team has not sent (open or cancelled). */
          var req = q.source === 'website' && !q.released_at && !q.sent_out_at && !q.signed_at && !q._revised && !q.removed_at;
          if (q.removed_at) items.push('<button class="kmenu-item" data-g="1" data-a="pdf" type="button" role="menuitem">Download PDF</button>');
          /* The quotation's link (2026-11-08): one item opening a card with
             the address, Copy link and Preview, so the ⋯ keeps to seven.
             Copy link is the prospect's own link, to send again by hand,
             once the team has sent the quotation (2026-10-30); a team's
             quotation has one too, made at the first Copy link, so the
             client signs on it (QUOTATION SIGNING, 2026-10-31). Preview
             opens the prospect's page read only, for any reader. */
          var canCopy = !q.removed_at && !awaiting(q) && !q._revised && q.status !== 'not_proceeding' && (q.access_key || maySet);
          var canPreview = !!(q.access_key && !q.removed_at);
          if (canCopy || canPreview) {
            items.push('<button class="kmenu-item" data-g="1" data-a="linkcard" type="button" role="menuitem"' +
              (canCopy ? ' data-copy' : '') + (canPreview ? ' data-preview' : '') + '>Show quotation link</button>');
          }
          /* Send on WhatsApp (2026-10-14): the quotation's PDF to a contact,
             drawn only once the template is on (`waOn` below). */
          var acts = [];
          /* A website quotation is revised from its row: Build quote on a
             copy, linked as its revision, then sent (2026-10-26). */
          /* Two ways to show the rates (the user, 2026-10-31): Publish shows
             them on the prospect's link alone; Send quotation shows them and
             sends the quotation-ready WhatsApp, drawn once its template is on
             (`data-wa-ready`) and never for a prospect marked Do not contact,
             which quotation_send refuses (audit 2026-10-30). */
          if (maySet && askable(q)) {
            if (!q.no_contact_at) acts.push('<button class="btn btn-sm" data-a="send" data-wa-ready data-gate="whatsapp quotewa" hidden type="button">Send quotation</button>');
            acts.push('<button class="btn btn-sm" data-a="publish" type="button">Publish</button>');
          }
          /* A signed quotation is the contract: asked again, never revised
             over (audit 2026-11-04). */
          /* A team's quotation is edited from its row too: in place until
             sent out, else its revision (2026-11-06; on the row since
             2026-11-08, so the ⋯ keeps to seven). */
          /* Edit goes into the ⋯ with Download (the user, 2026-11-13, C),
             unless the ⋯ would pass seven: then it is the commonest act and
             stays on the row (DESIGN.md §5 Menus 8). */
          var edit = (maySet && !q.removed_at && q.source !== 'website' && editable(q)) || (maySet && awaiting(q) && editable(q));
          if (maySet && !q.removed_at && q.change_requested_at && !q._revised && !q.signed_at && q.status !== 'not_proceeding') {
            /* The prospect's changes open in Build quote, made the next revision. */
            acts.push('<button class="btn btn-sm" data-a="adjust" type="button">Adjust and send</button>');
          } else if (maySet && awaiting(q) && editable(q)) {
            /* Its Edit is below. */
          } else if (maySet && !q.removed_at && q.source === 'website' && !q._revised && !q.signed_at && st[1] !== 'is-off' && q.status !== 'not_proceeding') {
            acts.push('<button class="btn btn-sm" data-a="adjust" type="button">Adjust and send</button>');
          }
          /* Signed: the colleague checks the entries and submits them to a
             reviewer; the reviewer (or an admin) reviews (2026-10-31). The
             act stands on the row: it is what the quotation waits on. */
          if (maySet && !q.removed_at && q.signed_at && !q.reviewed_at && (!q.submitted_at || q.returned_at)) {
            acts.push('<button class="btn btn-sm" data-a="check" type="button">Submit</button>');
          }
          if (maySet && !q.removed_at && mayReview(q)) acts.push('<button class="btn btn-sm" data-a="review" type="button">Review</button>');
          /* An approved quotation's invoices, made in Bukku as drafts a
             billing cycle (QUOTATION INVOICES, 2026-11-17). */
          if (!q.removed_at && q.reviewed_at && (ctx.may('clients.billing', 'view') || ctx.may('clients.quotes', 'view'))) acts.push('<button class="btn btn-sm" data-a="invoices" type="button">Invoices</button>');
          /* No Letter of Offer is issued from a quotation (2026-10-31): the
             client signs the quotation itself, which is the contract. */
          if (maySet && !q.removed_at) {
            /* A team's quotation is edited from its ⋯: in place until sent
               out, else its revision (2026-11-06). A website one is the
               row's Edit or Adjust and send. */
            /* No Duplicate (the user, 2026-11-13: "Remove Duplicate, move
               Edit into the menu"): Build quote makes a new one. */
            /* Send on WhatsApp (2026-10-14): the quotation's PDF to a contact,
               drawn only once the template is on (`waOn` below). */
            if (WA() && WA().may('quotation') && q.status !== 'not_proceeding' && !awaiting(q)) {
              items.push('<button class="kmenu-item" data-g="3" data-a="wa" data-wa data-gate="whatsapp" hidden type="button" role="menuitem">Send on WhatsApp</button>');
            }
            /* Send by email beside it (2026-10-31): optional as WhatsApp is,
               never sent by itself. */
            if (window.ADspaceDocMail && window.ADspaceDocMail.may('quotation') && q.status !== 'not_proceeding' && !awaiting(q) && !q.no_contact_at) {
              items.push('<button class="kmenu-item" data-g="3" data-a="mail" data-gate="email" type="button" role="menuitem">Send by email</button>');
            }
            /* The quotation-ready WhatsApp again, its link button the
               prospect's own (2026-10-30): a website quotation the team has
               sent, still valid, drawn once its template is on. A team's
               quotation sends the same message to its primary contact, its
               link opening the signing steps (2026-10-31), until signed. */
            if (!awaiting(q) && !q._revised && !q.no_contact_at && q.status !== 'not_proceeding' &&
                !(q.valid_until && q.valid_until < window.ADspaceClock.today()) &&
                (q.source === 'website' ? !!q.access_key : !q.signed_at)) {
              /* The step an unsigned quotation waits on stands on the row
                 (2026-11-07: the ⋯ held ten). */
              acts.push('<button class="btn btn-sm" data-a="resend" data-wa-ready data-gate="whatsapp" hidden type="button">' +
                (q.source === 'website' ? 'Resend on WhatsApp' : 'Send link on WhatsApp') + '</button>');
            }
            /* A signing on paper, keyed in by the team (2026-10-31). */
            if (!q.signed_at && offerable(q, live)) items.push('<button class="kmenu-item" data-g="4" data-a="paper" type="button" role="menuitem">Mark signed</button>');
            /* The signature set aside and kept, so the client signs again;
               never once reviewed. */
            if (q.signed_at && !q.reviewed_at) items.push('<button class="kmenu-item" data-g="5" data-a="resign" type="button" role="menuitem">Request again</button>');
            /* A website request not yet sent is three groups (the user,
               2026-11-27): Download PDF, Show quotation link, Ask for
               details · Edit, Cancel quote · Delete; no Do not contact
               (Allow contact stays where one is marked, its way back). */
            if (q.source === 'website' && (q.no_contact_at || !req)) {
              items.push(q.no_contact_at
                ? '<button class="kmenu-item" data-g="4" data-a="contact" type="button" role="menuitem">Allow contact</button>'
                : '<button class="kmenu-item" data-g="4" data-a="no_contact" type="button" role="menuitem">Do not contact</button>');
            }
            /* A signed quotation is the client's record: no Cancel or Remove
               (Request again sets the signature aside; audit 2026-11-04). */
            /* A website request is asked for details, or Not quoted with a
               reason, never Cancelled; a closed one is reopened (QUOTE
               DETAILS ASKED, 2026-11-27). */
            if (askable(q) && !q.no_contact_at) {
              items.push('<button class="kmenu-item" data-g="1" data-a="ask" type="button" role="menuitem">' + (q.details_asked_at && !q.details_at ? 'Ask again' : 'Ask for details') + '</button>');
            }
            if (q.match && !q.match_taken && !q._revised) {
              items.push('<button class="kmenu-item" data-g="4" data-a="brand" type="button" role="menuitem">Add as a new brand of ' + esc(q.match.name || 'the client') + '</button>');
              items.push('<button class="kmenu-item" data-g="4" data-a="keeplead" type="button" role="menuitem">Keep as a new lead</button>');
            }
            if ((awaiting(q) && !askable(q)) || (q.source === 'website' && !q.released_at && q.not_quoted && q.status === 'not_proceeding')) {
              items.push('<button class="kmenu-item" data-g="2" data-a="reopen" type="button" role="menuitem">Reopen</button>');
            } else if (askable(q)) {
              items.push('<button class="kmenu-item" data-g="2" data-a="notquote" type="button" role="menuitem">Cancel quote</button>');
            } else if (!q.reviewed_at && q.status === 'not_proceeding') {
              items.push('<button class="kmenu-item" data-g="5" data-a="proceeding" type="button" role="menuitem">Restore</button>');
            } else if (!q.signed_at) {
              items.push('<button class="kmenu-item" data-g="5" data-a="not_proceeding" type="button" role="menuitem">Cancel</button>');
            }
            /* A request is deleted, never removed: at Full control with its
               reference typed back, at Edit a request (js/delreq.js). One
               sent out or signed keeps its own menu and is never deleted. */
            if (req) items.push('<button class="kmenu-item is-danger" data-g="6" data-a="delete" data-need="clients.quotes:manage" type="button" role="menuitem">Delete</button>');
            else if (!q.signed_at) items.push('<button class="kmenu-item is-danger" data-g="6" data-a="remove" data-soft type="button" role="menuitem">Remove</button>');
            /* Once signed it is withdrawn from a day, never deleted (QUOTATION
               WAYS OUT, 2026-11-17), at Full Access. */
            if (q.signed_at && !q.withdrawn_at && ctx.may('clients.quotes', 'manage')) {
              items.push('<button class="kmenu-item" data-g="5" data-a="withdraw" data-need="clients.quotes:manage" type="button" role="menuitem">Mark withdrawn</button>');
            }
          }
          if (maySet && q.removed_at) items.push('<button class="kmenu-item" data-g="5" data-a="restore" type="button" role="menuitem">Restore</button>');
          /* The signed document's record (SIGNED DOCUMENT SEAL, 2026-11-17):
             every step to the second, and its seal once confirmed. */
          if (q.signed_at && !q.removed_at) items.unshift('<button class="kmenu-item" data-g="1" data-a="record" type="button" role="menuitem">Show document record</button>');
          if (!q.removed_at) items.unshift('<button class="kmenu-item" data-g="1" data-a="pdf" type="button" role="menuitem">Download PDF</button>');
          if (edit) items.splice(2, 0, '<button class="kmenu-item" data-g="2" data-a="edit" type="button" role="menuitem">Edit</button>');
          return '<div class="svc-row qt-row' + (q.removed_at || st[1] === 'is-off' ? ' is-off' : '') + (acts.length || !q.removed_at ? ' has-acts' : '') + '" data-id="' + esc(q.id) + '">' +
            /* A date holds together on a phone (2026-10-20, CLI-10). */
            '<span class="svc-name qt-name"><b class="qt-ref">' + window.ADspaceCopy.ref(refOf(q)) + '</b>' +
              (q.no_contact_at ? '<span class="chip qt-tag">Do not contact</span>' : '') +
              '<small>' + wholeDays(esc(metaOf(q))) + '</small><small>' + wholeDays(esc(fromOf(q))) + '</small>' +
              (q.match && !q.match_taken ? '<small class="qt-match">' + esc('Matches existing client · ' + (q.match.name || '')) + '</small>' : '') +
              (askedStart(q) ? '<small class="qt-start">' + wholeDays(esc('Preferred start ' + window.ADspaceClock.date(askedStart(q)))) + '</small>' : '') + '</span>' +
            '<span class="svc-rate svc-amt qt-amt"><b>' + esc(h[0]) + '</b>' + (h[1] ? '<small>' + esc(h[1]) + '</small>' : '') + '</span>' +
            '<span class="qt-state"><span class="chip-state ' + st[1] + '">' + esc(st[0]) + '</span>' +
              (st[2] ? '<small>' + wholeDays(esc(st[2])) + '</small>' : '') + '</span>' +
            '<span class="qt-dl">' + (q.removed_at ? '' : '<button class="btn btn-sm" data-a="view" type="button">Preview PDF</button>') + acts.join('') + '</span>' +
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
        var items = ['<button class="kmenu-item" data-g="1" data-a="pdf" type="button" role="menuitem">Download PDF</button>'];
        /* One that reached the client or was signed stays, Void (2026-11-26). */
        if (maySet && !q.sent_out_at && !q.signed_at) items.push('<button class="kmenu-item is-danger" data-g="6" data-a="delete" data-need="clients.quotes:manage" type="button" role="menuitem">Delete</button>');
        return '<div class="qt-gonerow" data-id="' + esc(q.id) + '"><span class="qt-gonename"><b class="qt-ref">' + window.ADspaceCopy.ref(refOf(q)) + '</b>' +
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
    if (ctx.painted) ctx.painted();
    var g = $('qtGone');
    if (g) g.addEventListener('click', function () { showRemoved = !showRemoved; paint(host, ctx, rows); });
    if (host.querySelector('[data-wa-ready]') && WA()) {
      WA().on('quote_ready').then(function (yes) {
        /* Sending also asks Send WhatsApp (GROUP SWITCHES, 2026-11-17). */
        var A = window.ADspaceAdmin;
        if (!yes || !(A && A.may && A.may('send.whatsapp', 'work'))) return;
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
        fitMenus(host);
      });
    }
    fitMenus(host);
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
          if (it.getAttribute('data-a') === 'linkcard') { linkCard(q, ctx, it, btn); return; }
          act(it.getAttribute('data-a'), q, ctx, host, btn);
        });
      });
    });
  }

  /* A ⋯ keeps to seven items shown (DESIGN.md §5 Menus 8): where the sends
     make it eight, Edit, the commonest act, stands on the row instead. The
     item itself moves, so it keeps its press (2026-11-13). */
  function fitMenus(host) {
    Array.prototype.forEach.call(host.querySelectorAll('.qt-row[data-id]'), function (row) {
      var menu = row.querySelector('[data-menu]'), ed = menu && menu.querySelector('[data-a="edit"]'), dl = row.querySelector('.qt-dl');
      if (!ed || !dl || menu.querySelectorAll('.kmenu-item:not([hidden])').length <= 7) return;
      ed.className = 'btn btn-sm'; ed.removeAttribute('role'); ed.removeAttribute('data-g');
      var view = dl.querySelector('[data-a="view"]');
      dl.insertBefore(ed, view ? view.nextSibling : dl.firstChild);
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
  /* SIGNED DOCUMENT SEAL (2026-11-17): a confirmed quotation's PDF is the
     sealed copy, drawn once with its Record of this Document and kept
     private; every Download, send and Preview hands that file over. One
     confirmed before the seal, or whose first keep failed, is sealed at its
     next Download by a colleague at Work; anyone else reads it drawn. */
  function sealOn() { var s3 = (window.ADSPACE_CONFIG || {}).s3; return Boolean(s3 && s3.privateInvoices && window.ADspaceSeal && window.ADspaceAdmin && window.ADspaceAdmin.putToS3); }
  function verifyUrl(q) { return window.ADSPACE_CONFIG.verify.page + '?s=' + encodeURIComponent(q.ref); }
  function readSealed(q, ctx) {
    return ctx.db.functions.invoke('sign-download', { body: { quotation: q.id } }).then(function (r) {
      var b = r && r.data;
      if (r.error || !b || typeof b.size !== 'number' || !b.size) throw new Error('kept-unread');
      return b.type === 'application/pdf' ? b : new Blob([b], { type: 'application/pdf' });
    });
  }
  var sealing = {};
  function sealNow(q, ctx) {
    if (sealing[q.id]) return sealing[q.id];
    var s3 = (window.ADSPACE_CONFIG || {}).s3 || {}, blob;
    var job = ctx.db.rpc('quotation_record', { p_id: q.id }).then(function (r) {
      var rec = r.data || {};
      if (r.error || rec.error) throw new Error(said(r.error || rec.error));
      return drawPlain(q, ctx, { seal: { record: rec, verifyUrl: verifyUrl(q) } });
    }).then(function (b) {
      blob = b;
      return ctx.db.functions.invoke(s3.functionName || 'sign-upload', {
        body: { ext: 'pdf', clientId: q.client_id, size: b.size, private: true, purpose: 'seal', quotationId: q.id, sha256: b.seal.sha } });
    }).then(function (r) {
      var d = r.data || {};
      if (r.error || !d.uploadUrl || !d.key) throw new Error(d.error || 'The sealed copy could not be saved. Please try again.');
      /* The hash is signed into the PUT: S3 keeps this file or none (2026-11-24). */
      return window.ADspaceAdmin.putToS3(d.uploadUrl, blob, d.contentType || 'application/pdf', null,
        d.checksum ? { 'x-amz-checksum-sha256': d.checksum } : null).then(function () {
        return ctx.db.rpc('quotation_seal', { p_id: q.id, p_key: d.key, p_sha: blob.seal.sha, p_pages_sha: blob.seal.pagesSha });
      });
    }).then(function (r) {
      var d = r.data || {};
      if (r.error || d.error) throw new Error(said(r.error || d.error));
      q.sealed_at = q.sealed_at || new Date().toISOString();
      /* Sealed first by someone else: theirs is the file kept. */
      if (d.kept) return readSealed(q, ctx);
      q.seal_sha = blob.seal.sha; q.seal_pages_sha = blob.seal.pagesSha;
      return blob;
    });
    sealing[q.id] = job;
    job.catch(function () { return null; }).then(function () { delete sealing[q.id]; });
    return job;
  }
  /* The demo (js/demo.js) keeps no stored file: its sealed sample is drawn
     here as the sealing draws it, from the record before it was sealed,
     and the demo keeps the hash of each copy it hands out for /verify/'s
     File check on the sample data (2026-11-20). */
  function sealedCopy(q, client) {
    var ctx = { db: window.ADspaceAPI.client, client: client || {} };
    return ctx.db.rpc('quotation_record', { p_id: q.id }).then(function (r) {
      var rec = r.data || {};
      if (r.error || rec.error) throw new Error(said(r.error || rec.error));
      rec.steps = (rec.steps || []).filter(function (s) { return s.step !== 'sealed'; });
      rec.seal = null;
      return drawPlain(q, ctx, { seal: { record: rec, verifyUrl: verifyUrl(q) } });
    });
  }
  function drawPdf(q, ctx, extra) {
    if (!(extra && extra.draft)) {
      if (q.sealed_at) return readSealed(q, ctx);
      if (q.reviewed_at && sealOn() && ctx.may('clients.quotes', 'work')) {
        return sealNow(q, ctx).catch(function () { return drawPlain(q, ctx, extra); });
      }
    }
    return drawPlain(q, ctx, extra);
  }
  /* A signed quotation is drawn in the words it was signed in (the review
     of 2026-11-24): the cover kept at signing (`signed_words.cover`) and the
     agency's name and Service Terms address kept at its submit, never
     today's. */
  function keptWords(q) { var w = q.signed_at && q.signed_words; return w && typeof w === 'object' ? w : null; }
  function drawPlain(q, ctx, extra) {
    var c = ctx.client || {};
    var by = q.made_by || (q.source === 'website' ? c.owner : '') || '';
    var kept = keptWords(q);
    return Promise.all([kept && kept.cover ? Promise.resolve(kept.cover) : coverWords(ctx), roleOf(ctx, by)]).then(function (got) {
      var named = q.contact && q.contact.name;
      var o = { attention: named || ctx.attention || '', attentionRole: named ? '' : (ctx.attentionRole || ''),
        to: { name: c.legal_name || c.name || q.brand, address: c.billing_address || '' },
        cover: got[0], preparedBy: { name: by, designation: got[1] }, client: c,
        agency: kept && kept.agency ? kept.agency : null, termsUrl: kept && kept.agency ? (kept.terms_url || '') : null };
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

  /* The Link card (2026-11-08): the quotation's address, Copy link and
     Preview, hung from the row's ⋯ as the Ad IDs card is. */
  var linkPop = null, linkBtn = null;
  function linkShut(back) {
    if (!linkPop || linkPop.hidden) return;
    linkPop.hidden = true;
    if (linkBtn) { linkBtn.setAttribute('aria-expanded', 'false'); if (back) linkBtn.focus(); }
  }
  function linkCard(q, ctx, item, anchorBtn) {
    if (!linkPop) {
      linkPop = document.createElement('div');
      linkPop.className = 'kmenu rp-idspop qt-linkpop'; linkPop.id = 'qtLinkPop'; linkPop.setAttribute('data-page-link', 'quote'); linkPop.hidden = true; linkPop.tabIndex = -1;
      linkPop.setAttribute('role', 'dialog'); linkPop.setAttribute('aria-labelledby', 'qtLinkTitle');
      document.body.appendChild(linkPop);
      linkPop.addEventListener('click', function (e) { e.stopPropagation(); });
      document.addEventListener('click', function () { linkShut(); });
      window.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && linkPop && !linkPop.hidden) { e.stopImmediatePropagation(); e.preventDefault(); linkShut(true); }
      }, true);
      if (window.ADspaceMenu) window.ADspaceMenu.onScroll(function () { linkShut(); });
    }
    if (linkBtn && linkBtn !== anchorBtn) linkBtn.setAttribute('aria-expanded', 'false');
    linkBtn = anchorBtn;
    var url = q.access_key ? location.origin + '/quote/?q=' + encodeURIComponent(q.access_key) : '';
    var canCopy = item.hasAttribute('data-copy'), canPreview = item.hasAttribute('data-preview');
    linkPop.innerHTML = '<div class="popcard-head"><p class="rp-idspop-title" id="qtLinkTitle">' + esc(q.ref) + '</p>' +
      '<button class="iconbtn popcard-x" type="button" data-a="x" aria-label="Close">' + window.ADspaceIcons.glyph('x') + '</button></div>' +
      (url ? '<p class="qt-linkaddr">' + esc(url.replace(/^https?:\/\//, '')) + '</p>' : '') +
      '<div class="rp-idspop-acts">' +
        (canPreview && url ? '<button class="btn btn-sm" type="button" data-a="preview">Preview</button>' : '') +
        (canCopy ? '<button class="btn btn-sm" type="button" data-a="link">Copy link</button>' : '') + '</div>';
    Array.prototype.forEach.call(linkPop.querySelectorAll('[data-a="preview"], [data-a="link"]'), function (b) {
      b.onclick = function () {
        var a2 = b.getAttribute('data-a');
        act(a2, q, ctx, null, b);
        if (a2 === 'preview') linkShut();
      };
    });
    linkPop.querySelector('[data-a="x"]').onclick = function () { linkShut(true); };
    /* Shown a tick later: the press on the ⋯ item is still on its way to
       the page, whose click shuts the card. */
    setTimeout(function () {
      linkPop.hidden = false;
      anchorBtn.setAttribute('aria-expanded', 'true');
      if (window.ADspaceMenu) window.ADspaceMenu.pop(anchorBtn, linkPop, 'left');
      try { linkPop.focus({ preventScroll: true }); } catch (e) { linkPop.focus(); }
    }, 0);
  }

  function act(a, q, ctx, host, btn) {
    if (a === 'preview') { window.open('/quote/?q=' + encodeURIComponent(q.access_key) + '&preview=1', '_blank', 'noopener'); return; }
    if (a === 'link') {
      var copy = function (key) { window.ADspaceCopy.to(btn, location.origin + '/quote/?q=' + encodeURIComponent(key)); ctx.msg('qtMsg', 'Link copied.', 'ok'); };
      /* Copied again, the link is copied at once and the copy still told,
         so the copier's own opening is never taken for the client's
         (QUOTATION COPIER'S OPENING, 2026-11-25). */
      if (q.access_key) { copy(q.access_key); ctx.db.rpc('quotation_link', { p_id: q.id }).then(function () {}).catch(function () {}); return; }
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
        body: 'The signature on ' + q.ref + ' will be kept, and the client will be asked to sign again on the quotation link.' }, function () {
        ctx.db.rpc('quotation_resign', { p_id: q.id }).then(function (r) {
          var d = r.data || {};
          if (r.error || d.error) { ctx.msg('qtMsg', said(r.error || d.error), 'err'); return; }
          ctx.reload(function () { ctx.msg('qtMsg', q.ref + ' is open for signing again.', 'ok'); });
        }).catch(function (e) { ctx.msg('qtMsg', said(e), 'err'); });
      });
      return;
    }
    if (a === 'invoices') { openInvoices(q, ctx, btn); return; }
    if (a === 'record') {
      window.ADspaceSeal.open({ title: 'Record of this Document', sub: 'Quotation ' + q.ref, opener: btn, verifyUrl: verifyUrl(q), checks: { kind: 'quotation', id: q.id },
        load: function () {
          return ctx.db.rpc('quotation_record', { p_id: q.id }).then(function (r) {
            if (r.error) throw r.error;
            return r.data;
          });
        },
        download: function (b) { act('pdf', q, ctx, host, b); } });
      return;
    }
    if (a === 'pdf' || a === 'view') {
      if (!window.ADspaceQuotePdf) return;
      var tab = a === 'view' ? window.ADspaceDocs.previewTab()
        : window.ADspaceDocs && window.ADspaceDocs.tabFor ? window.ADspaceDocs.tabFor() : null;
      var dq = isDraft(q) ? Object.assign({}, q, { ref: refOf(q) }) : q;
      drawPdf(dq, ctx, isDraft(q) ? { draft: true } : null).then(function (blob) {
        window.ADspaceDocs.save(blob, window.ADspaceQuotePdf.fileName(dq), tab);
      }).catch(function (e) {
        if (tab) try { tab.close(); } catch (x) {}
        ctx.msg('qtMsg', said(e) || 'The PDF could not be generated.', 'err');
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
    if (a === 'confirm') {
      window.ADspaceConfirm.ask({ title: 'Confirm quotation?',
        body: 'This quotation will take its reference' + (q.revises ? ' as the next revision of the quotation it revises' : '') +
          '. It can then be sent to the client. A confirmed quotation cannot be returned to a draft.',
        go: 'Confirm quotation', wait: true }, function () {
        return ctx.db.rpc('quotation_confirm', { p_id: q.id }).then(function (r) {
          var d = r.data || {};
          if (r.error) return said(r.error);
          if (d.error === 'revised') return 'The quotation it revises has since been revised as ' + d.ref + '. Remove this draft, or edit ' + d.ref + ' instead.';
          if (d.error) return said(d.error);
          ctx.reload(function () { ctx.msg('qtMsg', d.ref + ' confirmed.', 'ok'); });
          return '';
        }).catch(function (e) { return said(e); });
      });
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
        body: q.ref + ' will be shown to ' + who + ' on the quotation link and sent on WhatsApp. It is valid for ' +
          validFor(q) + ' days from today.',
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
        body: q.ref + ' will be shown to ' + whom + ' on the quotation link. No WhatsApp message will be sent. It is valid for ' +
          validFor(q) + ' days from today.',
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
      var team = q.source !== 'website';
      var to = team ? ((ctx.contact && ctx.contact.name) || q.brand) : ((q.contact && q.contact.name) || q.brand);
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
          if (team && d.key && !q.access_key) q.access_key = d.key;
          ctx.msg('qtMsg', q.ref + (team ? ' link sent on WhatsApp.' : ' sent again on WhatsApp.'), 'ok');
        }).catch(function (e) { if (btn) btn.disabled = false; ctx.msg('qtMsg', said(e), 'err'); });
      };
      window.ADspaceConfirm.ask(team ? { title: 'Send link on WhatsApp?',
        body: 'The Quotation ready message, with the link to review and sign ' + q.ref + ', will be sent to ' + to + '.', go: 'Send' } : { title: 'Resend on WhatsApp?',
        body: 'The Quotation ready message, with the link to ' + q.ref + ', will be sent to ' + to + ' again.', go: 'Send' }, function () { go(false); });
      return;
    }
    if (a === 'withdraw') { withdraw(q, ctx); return; }
    if (a === 'ask') { askDetails(q, ctx); return; }
    if (a === 'notquote') { notQuote(q, ctx); return; }
    if (a === 'reopen') { reopen(q, ctx, false); return; }
    if (a === 'brand' || a === 'keeplead') { takeMatch(q, ctx, a === 'brand' ? 'brand' : 'lead'); return; }
    if (a === 'adjust') { build(ctx, q.change_requested_at && q.change_request && q.change_request.selection ? q.change_request.selection : q.selection, btn, q); return; }
    /* A quotation a letter or service lines came from keeps its figures:
       Edit makes its revision, as once sent out (2026-11-07). */
    if (a === 'edit') { if (sentOut(q) || (q._lines || []).length) build(ctx, q.selection, btn, q); else build(ctx, q.selection, btn, null, q); return; }
    if (a === 'delete') { remove(q, ctx); return; }
    var back = { not_proceeding: 'proceeding', remove: 'restore' }[a];
    set(q, a, ctx, function () {
      if (!back) { ctx.msg('qtMsg', a === 'restore' || a === 'proceeding' ? 'Restored.' : a === 'no_contact' ? q.ref + ' marked Do not contact.' : 'Saved.', 'ok'); return; }
      ctx.undo(q.ref + (a === 'remove' ? ' removed.' : ' cancelled.'), function () {
        set(q, back, ctx, function () {});
      }, $('qtMsg'));
    });
  }
  /* Mark withdrawn (QUOTATION WAYS OUT, 2026-11-17): a signed quotation
     stops from a day, with a reason; its sealed copy is kept and reads
     Withdrawn; the service lines its approval confirmed go back to To
     quote where asked. Undo where it happened puts it all back. */
  var OUT_SAID = {
    denied: 'You do not have permission to withdraw quotations. Please ask an admin.',
    'not-signed': 'Only a signed quotation can be withdrawn. Cancel this one instead.',
    withdrawn: 'This quotation is already withdrawn.',
    'bad-date': 'Choose a date between the signing date and today.',
    'bad-reason': 'Enter a reason.'
  };
  function withdraw(q, ctx) {
    var today = window.ADspaceClock.today(), signedDay = window.ADspaceClock.day(q.signed_at);
    var fields = [{ name: 'on', label: 'Withdrawn from', type: 'date', required: true, value: today, min: signedDay, max: today },
      { name: 'reason', label: 'Reason', required: true }];
    if (q.reviewed_at) fields.push({ name: 'lines', label: 'Revert its confirmed service lines to To quote', tick: true, value: 'on' });
    window.ADspaceConfirm.ask({
      title: 'Mark withdrawn?',
      body: q.ref + ' will read Withdrawn in Quotations and on the verify page. The signed copy is kept.',
      fields: fields, go: 'Mark withdrawn', tone: 'warn',
      check: function (v) { return v.on < signedDay || v.on > today ? 'Choose a date between the signing date and today.' : ''; },
      wait: true
    }, function (v) {
      return ctx.db.rpc('quotation_withdraw', { p_id: q.id, p_on: v.on, p_reason: v.reason, p_lines: v.lines === 'on' }).then(function (r) {
        var d = r.data || {};
        if (r.error || d.error) return OUT_SAID[d.error] || said(r.error || d.error);
        var n = d.lines || 0;
        ctx.reload(function () {
          ctx.undo(q.ref + ' withdrawn.' + (n ? ' ' + n + (n === 1 ? ' service line' : ' service lines') + ' reverted to To quote.' : ''), function () {
            ctx.db.rpc('quotation_withdraw_undo', { p_id: q.id }).then(function (u) {
              var e = u.error || (u.data && u.data.error);
              if (e) { ctx.msg('qtMsg', said(e), 'err'); return; }
              ctx.reload(function () { ctx.msg('qtMsg', 'Undone.', 'ok'); });
            }).catch(function (e) { ctx.msg('qtMsg', said(e), 'err'); });
          }, $('qtMsg'));
        });
        return '';
      }).catch(function (e) { return said(e); });
    });
  }
  /* Ask for details (QUOTE DETAILS ASKED, 2026-11-27): what the request
     lacks ticked as the question opens, a note, then Send email (to the
     address the prospect typed, in their language) or Copy for WhatsApp,
     sent by hand. Either keeps the request Waiting for details until its
     Reply by; the prospect's own link opens the fields ticked alone. */
  var ASK_SAID = {
    denied: 'You do not have permission to ask for details. Please ask an admin.',
    sent: 'This quotation has been sent. Refresh the page.', closed: 'This request is closed. Reopen it first.',
    'bad-fields': 'Tick at least one detail, or enter a note.', 'bad-note': 'Enter a note of up to 500 characters, without a web address.',
    'no-contact': 'This prospect is marked Do not contact. Choose Allow contact first.',
    'no-email': 'This prospect gave no email address. Choose Copy for WhatsApp.',
    'email-off': window.ADspaceWords.line.emailHandOff,
    'send-off': window.ADspaceWords.line.emailPortalOff,
    'not-sent': 'Not sent. Please try again.', 'not-confirmed': 'Sent, but its delivery could not be confirmed. Check the Email tab before sending again.',
    'needs-update': 'This feature is not available yet. Please contact an admin.'
  };
  var ASK_FIELDS = [['registration', 'Business Registration No. and Registered Name'], ['industry', 'Industry'],
    ['online', 'Website or social media account'], ['commence', 'Planned commencement']];
  function lacks(q) {
    var k = q.contact || {};
    return { registration: !k.brn || !k.legal, industry: !k.industry, online: !k.website && !k.handle, commence: !k.commence };
  }
  function askVals(v) {
    return { f: ASK_FIELDS.map(function (x) { return x[0]; }).filter(function (k) { return v[k] === 'on'; }), note: (v.note || '').trim() };
  }
  function askDetails(q, ctx) {
    var miss = q.details_asked_at && q.details_ask ? (q.details_ask.fields || []).reduce(function (o, k) { o[k] = true; return o; }, {}) : lacks(q);
    var note = q.details_asked_at && q.details_ask ? q.details_ask.note || '' : '';
    var byMail = !!(window.ADspaceDocMail && window.ADspaceDocMail.may('quotation')), to = (q.contact || {}).email;
    var ask = function (v) {
      var x = askVals(v);
      return ctx.db.rpc('quotation_details_ask', { p_id: q.id, p_fields: x.f, p_note: x.note || null }).then(function (r) {
        var d = r.data || {};
        if (r.error) return { why: /function|schema cache/i.test(r.error.message || '') ? ASK_SAID['needs-update'] : said(r.error) };
        if (d.error) return { why: ASK_SAID[d.error] || said(d.error) };
        return d;
      }).catch(function (e) { return { why: said(e) }; });
    };
    var done = function (line) {
      ctx.reload(function () { ctx.msg('qtMsg', line, 'ok'); });
    };
    var copy = { label: 'Copy for WhatsApp', gate: 'whatsapp', run: function (v, b) {
      var x = askVals(v);
      if (!x.f.length && !x.note) return Promise.resolve(ASK_SAID['bad-fields']);
      var why = '';
      var words = ask(v).then(function (d) { if (d.why) { why = d.why; return null; } return d.text || null; });
      return window.ADspaceCopy.later(b, words).then(function (copied) {
        if (why) return why;
        done(copied ? 'Copied. Paste it into WhatsApp to ' + (((q.contact || {}).name) || 'the prospect') + '.' : 'Request saved, but the message was not copied. Choose Ask again to copy it.');
        return '';
      });
    } };
    window.ADspaceConfirm.ask({
      title: q.details_asked_at && !q.details_at ? 'Ask again' : 'Ask for details', wait: true,
      go: byMail ? 'Send email' : copy.label, gate: byMail ? 'email' : 'whatsapp',
      body: byMail && to ? 'Email to ' + to + '.' : '',
      alt: byMail ? copy : null,
      fields: ASK_FIELDS.map(function (x) { return { name: x[0], label: x[1], tick: true, value: miss[x[0]] ? 'on' : '' }; })
        .concat([{ name: 'note', label: 'Note', rows: 2, required: false, value: note }]),
      check: function (v) { var x = askVals(v); return !x.f.length && !x.note ? ASK_SAID['bad-fields'] : ''; }
    }, function (v, b) {
      if (!byMail) return copy.run(v, b);
      return ask(v).then(function (d) {
        if (d.why) return d.why;
        return ctx.db.functions.invoke('supplier-mail', { body: { quoteAsk: true, quotation: q.id } }).then(function (r) {
          var m = (r && r.data) || {};
          if (r.error || m.error) return ASK_SAID[m.error] || ASK_SAID['not-sent'];
          done('Email sent to ' + (m.to_name || m.to || to) + '.');
          return '';
        }).catch(function () { return ASK_SAID['not-sent']; });
      });
    });
  }
  /* Not quoted: a website request the team will not quote, with its reason;
     the prospect's link reads closed. Undo where it happened, Reopen from
     the ⋯ later. */
  function notQuote(q, ctx) {
    window.ADspaceConfirm.ask({
      title: 'Cancel quote', tone: 'warn', go: 'Cancel quote', cancel: 'Keep quote', wait: true,
      body: q.ref + ' will close, and the prospect\'s link will show the request as closed.',
      fields: [{ name: 'why', label: 'Reason', choices: [['incomplete', NOT_QUOTED.incomplete], ['fit', NOT_QUOTED.fit],
        ['duplicate', NOT_QUOTED.duplicate], ['spam', NOT_QUOTED.spam]], value: 'incomplete' }]
    }, function (v) {
      return ctx.db.rpc('quotation_not_quote', { p_id: q.id, p_reason: (v && v.why) || v }).then(function (r) {
        var d = r.data || {};
        if (r.error || d.error) return ASK_SAID[d.error] || said(r.error || d.error);
        ctx.reload(function () {
          ctx.undo(q.ref + ' not quoted.', function () { reopen(q, ctx, true); }, $('qtMsg'));
        });
        return '';
      }).catch(function (e) { return said(e); });
    });
  }
  function reopen(q, ctx, undo) {
    ctx.db.rpc('quotation_not_quote', { p_id: q.id, p_reason: null }).then(function (r) {
      var d = r.data || {};
      if (r.error || d.error) { ctx.msg('qtMsg', ASK_SAID[d.error] || said(r.error || d.error), 'err'); return; }
      ctx.reload(function () { ctx.msg('qtMsg', undo ? 'Undone.' : q.ref + ' reopened.', 'ok'); });
    }).catch(function (e) { ctx.msg('qtMsg', said(e), 'err'); });
  }
  /* Matches existing client (QUOTE INTAKE, 2026-11-27): the request made a
     new lead for another brand of a client the team keeps. Add as a new
     brand bills it through that client's entity (Billing's Remove takes
     it back); Keep as a new lead has its Undo here. */
  var MATCH_SAID = { 'no-entity': 'That client has no billing entity yet. Add one in its Billing first.', taken: 'Already chosen. Refresh the page.',
    denied: 'You do not have permission to change billing entities. Please ask an admin.' };
  function takeMatch(q, ctx, take) {
    var name = (q.match && q.match.name) || 'the client';
    var go = function () {
      return ctx.db.rpc('quotation_match_take', { p_id: q.id, p_take: take }).then(function (r) {
        var d = r.data || {};
        if (r.error || d.error) return MATCH_SAID[d.error] || said(r.error || d.error);
        ctx.reload(function () {
          if (take === 'lead') {
            ctx.undo('New lead kept.', function () {
              ctx.db.rpc('quotation_match_take', { p_id: q.id, p_take: null }).then(function (u) {
                var e = u.error || (u.data && u.data.error);
                if (e) { ctx.msg('qtMsg', MATCH_SAID[e] || said(e), 'err'); return; }
                ctx.reload(function () { ctx.msg('qtMsg', 'Undone.', 'ok'); });
              }).catch(function (e) { ctx.msg('qtMsg', said(e), 'err'); });
            }, $('qtMsg'));
          } else ctx.msg('qtMsg', 'Added as a new brand of ' + name + '.', 'ok');
        });
        return '';
      }).catch(function (e) { return said(e); });
    };
    if (take === 'lead') { go().then(function (why) { if (why) ctx.msg('qtMsg', why, 'err'); }); return; }
    window.ADspaceConfirm.ask({ title: 'Add as a new brand of ' + name + '?', go: 'Add', wait: true,
      body: q.brand + ' will be billed through ' + name + '\'s primary billing entity. It can be removed later in Billing.' }, go);
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
    denied: 'You do not have permission to delete quotations. Please ask an admin.',
    'not-removed': 'Remove this quotation first.',
    'bad-ref': 'The reference does not match.',
    sent: 'This quotation was sent or signed, so it cannot be deleted. It stays in Documents as Void.'
  };
  function remove(q, ctx) {
    window.ADspaceConfirm.ask({
      title: 'Delete',
      body: q.ref + ' will be deleted, and its reference will not be used again. This cannot be undone.',
      go: 'Delete', tone: 'danger', wait: true,
      field: { label: 'Type the reference to confirm', placeholder: q.ref, match: q.ref,
               need: 'Type the reference to confirm.', mismatch: 'The reference does not match.' }
    }, function () {
      return ctx.db.rpc('quotation_delete', { p_id: q.id, p_ref: q.ref }).then(function (r) {
        var d = r.data || {};
        if (r.error) return said(r.error);
        if (d.error === 'lines') return 'Service lines were created from ' + q.ref + '. Delete ' + (d.count === 1 ? 'that line' : 'those ' + d.count + ' lines') + ' in Service lines first.';
        if (d.error === 'letter') return 'Letter of Offer ' + d.number + ' quotes ' + q.ref + ', so the quotation cannot be deleted.';
        if (d.error === 'revised') return q.ref + ' was revised as ' + d.ref + '. Delete ' + d.ref + ' first.';
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
  var PEN_SVG = window.ADspaceIcons.glyph('pen');
  var CO = [['legal_name', 'Registered Company Name'], ['company_no', 'Business Registration No.'], ['company_no_old', 'Old Registration No.'],
    ['tin', 'TIN'], ['sst_no', 'SST Registration No.'], ['billing_address', 'Billing address'], ['finance_email', 'Finance email']];
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
  /* The signed name or number against the client record (QUOTATION BRAND
     AND COMPANY PICK, 2026-11-27): read as the database reads it, a
     difference of case or spacing alone none. */
  var PICK = ['legal_name', 'company_no'];
  function coDiffers(k, signedV, recV) {
    var a = coNorm(k, signedV), b = coNorm(k, recV);
    return PICK.indexOf(k) > -1 && a !== '' && b !== '' && a !== b;
  }
  function pickHtml(k, label, signedV, recV, chosen) {
    var nm = 'qsgPick-' + k;
    return '<small class="qsg-was"><span class="chip-state is-warn">Differs from the client record</span></small>' +
      '<span class="qsg-pick" role="radiogroup" aria-label="' + esc(label) + ' for the client record">' +
      '<label class="tickline"><input type="radio" name="' + nm + '" value="keep" data-pick="' + k + '"' + (chosen === 'keep' ? ' checked' : '') + '> <span>Keep ' + esc(recV) + '</span></label>' +
      '<label class="tickline"><input type="radio" name="' + nm + '" value="use" data-pick="' + k + '"' + (chosen === 'use' ? ' checked' : '') + '> <span>Use ' + esc(signedV) + '</span></label></span>';
  }
  function signedHtml(q, fix, edit, held, recCo, picks) {
    var s = q.signed || {}, co = s.company || {}, ct = s.contact || {}, sg = s.signer || {}, rec = s.record || {};
    var kept = s.record_pick || {};
    var was = {};
    (s.corrections || []).forEach(function (c) { if (!(c.field in was)) was[c.field] = c.from; });
    var rows = CO.map(function (f) {
      var k = f[0], v = fix && k in fix ? fix[k] : (co[k] || '');
      if ((!edit || held === true) && !v && !(k in was)) return '';
      var note = '';
      if (fix && k in fix) note = '<small class="qsg-was">Signed as ' + esc(co[k] || 'Not set') + '</small>';
      else if (k in was) note = '<small class="qsg-was">Signed as ' + esc(was[k] || 'Not set') + '</small>';
      if (edit && held === false && recCo && coDiffers(k, v, recCo[k])) note += pickHtml(k, f[1], v, recCo[k], picks && picks[k]);
      else if (!edit && kept[k] && kept[k].record) {
        note += '<small class="qsg-was">' + esc(kept[k].pick === 'use' ? 'Client record changes from ' + kept[k].record + ' on approval' : 'Client record keeps ' + kept[k].record) + '</small>';
      }
      return '<div><dt>' + esc(f[1]) + '</dt><dd class="mfield' + (v ? '' : ' is-empty') + (k === 'billing_address' ? ' is-pre' : '') + '">' +
        '<span class="mval" data-k="' + k + '">' + esc(v || 'Not set') + '</span>' +
        (edit && held === false ? '<button class="tl-pen" type="button" data-pen="' + k + '" aria-label="Edit ' + esc(f[1].toLowerCase()) + '">' + PEN_SVG + '</button>' : '') +
        note + '</dd></div>';
    }).join('');
    var sig = '';
    if (s.signature && s.signature.type === 'drawn') sig = '<span class="qsg-sig">' + window.ADspaceIcons.drawing('', '<path d="' + esc(s.signature.path) + '"/>', 'class="qsg-sig-svg" role="img" aria-label="Signature of ' + esc(sg.name || '') + '"') + '</span>';
    else if (s.signature && s.signature.type === 'typed') sig = '<span class="qsg-sig is-typed">' + esc(s.signature.text) + '</span>';
    var how = s.via === 'paper'
      ? fact('Signed', 'On paper') +
        fact('Entered by', esc((rec.by || '') + (rec.entered_at ? ' · ' + when(rec.entered_at) : ''))) +
        (s.scan && window.ADspaceWords.absUrl(s.scan) ? fact('Scan', '<a class="plink" href="' + esc(window.ADspaceWords.absUrl(s.scan)) + '" target="_blank" rel="noopener">Open scan</a>') : '')
      : fact('Signed', 'On the quotation link') +
        /* The code proves only the address it went to: one outside Contacts
           is said, so the reviewer checks who signed (audit 2026-11-04). */
        (rec.email ? fact('Code sent to', window.ADspaceWords.addr(rec.email) + (rec.in_contacts === false ? '<small class="qsg-was"><span class="chip-state is-warn">Not in Contacts</span></small>' : '')) : '') +
        (rec.ip ? fact('Signed from', esc(rec.ip + (rec.country ? ' · ' + rec.country : ''))) : '') +
        (rec.fingerprint ? fact('Fingerprint', '<span class="mono">' + esc(rec.fingerprint) + '</span>') : '');
    return '<section class="fsec"><h4 class="fsec-h">Company' + (edit && held === true ? '<small class="qsg-held">Kept in Bukku.</small>' : '') + '</h4>' +
      '<dl class="ovfacts qsg-facts">' + rows + '</dl></section>' +
      '<section class="fsec"><h4 class="fsec-h">Billing contact</h4><dl class="ovfacts qsg-facts">' +
        fact('Name', esc(window.ADspaceWords.person ? window.ADspaceWords.person(ct.salutation, ct.name) : ct.name || '')) +
        (ct.phone ? fact('Phone', esc(window.ADspaceAPI.phoneWord(ct.phone))) : '') + (ct.email ? fact('Email', window.ADspaceWords.addr(ct.email)) : '') + '</dl></section>' +
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
      sheetMsg(msgId, said(e) || 'The PDF could not be generated.', 'err');
    });
  }

  /* Check and submit. */
  var CK = null;
  function openCheck(q, ctx, opener) {
    if (!$('qsgCheckSheet') || !q.signed) return;
    /* A client whose billing Bukku holds keeps the company as signed: the
       approval leaves its Billing alone (`quotation_review` `held`), so the
       check offers no correction to it; asked of the database, as the
       approval reads it, and drawn without pens until it answers. */
    CK = { q: q, ctx: ctx, fix: {}, held: null, rec: null, pick: {} };
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
    ctx.db.rpc('bukku_link_get', { p_kind: 'client', p_id: q.client_id }).then(function (r) {
      var d = r.data || {};
      return Boolean(!r.error && d.held && !d.via);
    }).catch(function () { return false; }).then(function (held) {
      if (!CK || CK.q !== q) return;
      CK.held = held;
      if (held) CK.fix = {};
      paintCheck();
    });
    /* The client record's name and number, for a signed one that differs. */
    ctx.db.from('clients').select('legal_name, company_no').eq('id', q.client_id).maybeSingle().then(function (r) {
      if (!CK || CK.q !== q) return;
      CK.rec = r.error ? null : (r.data || null);
      paintCheck();
    }).catch(function () { return null; });
    ctx.db.rpc('quotation_reviewers', { p_id: q.id }).then(function (r) {
      if (!CK || CK.q !== q) return;
      var d = r.data || {};
      if (r.error || d.error) { sheetMsg('qsgCheckMsg', said(r.error || d.error), 'err'); return; }
      var list = d.reviewers || [];
      if (!list.length) { sheetMsg('qsgCheckMsg', 'No colleague can review this quotation. Please ask an admin to give a colleague Clients: Quotations at Full control.', 'err'); return; }
      sel.innerHTML = '<option value="">Choose a colleague</option>' + list.map(function (m) {
        return '<option value="' + esc(m.id) + '"' + (m.last ? ' selected' : '') + '>' + esc((m.code ? m.code + ' · ' : '') + m.name) + '</option>';
      }).join('');
      sel.disabled = false;
      $('qsgSubmit').disabled = false;
    }).catch(function (e) { if (CK && CK.q === q) sheetMsg('qsgCheckMsg', said(e), 'err'); });
  }
  function paintCheck() {
    var host = $('qsgCheckFacts'), q = CK.q;
    host.innerHTML = signedHtml(q, CK.fix, true, CK.held, CK.rec, CK.pick);
    Array.prototype.forEach.call(host.querySelectorAll('[data-pick]'), function (r) {
      r.addEventListener('change', function () { if (r.checked) CK.pick[r.getAttribute('data-pick')] = r.value; });
    });
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
    var fix = !CK.held && Object.keys(CK.fix).length ? CK.fix : null;
    var co = q.signed.company || {}, rec = null;
    if (CK.held === false && CK.rec) {
      var open = PICK.filter(function (k) { return coDiffers(k, k in CK.fix ? CK.fix[k] : co[k], CK.rec[k]); });
      var miss = open.filter(function (k) { return !CK.pick[k]; })[0];
      if (miss) {
        sheetMsg('qsgCheckMsg', SAID['pick-company'], 'err');
        var first = $('qsgCheckFacts').querySelector('[data-pick="' + miss + '"]');
        if (first) first.focus();
        return;
      }
      if (open.length) { rec = {}; open.forEach(function (k) { rec[k] = CK.pick[k]; }); }
    }
    go.disabled = true;
    /* The agency's name and Service Terms address as the quotation was
       signed under, kept once for its sealed copy (2026-11-24); a refusal
       here never holds the submit. */
    var cfg = window.ADSPACE_CONFIG || {};
    ctx.db.rpc('quotation_words_keep', { p_id: q.id, p_agency: cfg.agencyName || 'ADspace', p_terms_url: cfg.serviceTermsUrl || null })
      .then(function () { return null; }).catch(function () { return null; }).then(function () {
        var args = { p_id: q.id, p_reviewer: sel.value, p_company: fix };
        if (rec) args.p_record = rec;
        return ctx.db.rpc('quotation_submit', args);
      }).then(function (r) {
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
  var BILLING_SAID = { filled: 'Billing filled from the signed quotation.', updated: 'Billing updated from the signed quotation.', held: 'Billing not changed, as Bukku keeps this client\'s billing details.', kept: 'Billing not changed.' };
  /* The first day of next month in Malaysia: a new service's usual start. */
  function nextFirst() {
    var t = window.ADspaceClock.today(), y = Number(t.slice(0, 4)), m = Number(t.slice(5, 7));
    m += 1; if (m > 12) { m = 1; y += 1; }
    return y + '-' + (m < 10 ? '0' : '') + m + '-01';
  }
  function approve() {
    if (!RV) return;
    var q = RV.q, ctx = RV.ctx, me = meNow(), go = $('qsgApprove');
    var place = me && me.id !== q.reviewer_id;
    var c = ctx.client || {};
    /* Read from the database's own list where the reader cannot see Billing's
       values (only `billing_missing` arrives then). */
    var miss = Array.isArray(c.billing_missing) ? c.billing_missing : null;
    var empty = miss ? ['legal_name', 'company_no', 'billing_address'].every(function (f) { return miss.indexOf(f) > -1; })
      : !String(c.legal_name || '').trim() && !String(c.company_no || '').trim() && !String(c.billing_address || '').trim();
    window.ADspaceConfirm.ask({
      title: place ? 'Approve in place of ' + q.reviewer_name + '?' : 'Approve ' + q.ref + '?',
      body: (place ? q.reviewer_name + ' was asked to review it; the approval is filed under your name in their place. ' : '') +
        'Its items will become confirmed service lines' + (empty ? ', and Billing will be filled from the signed quotation.' : '. Billing will not change.'),
      /* Services start (2026-11-12, the user): the lines' first day, so the
         months they cover are read when a content month is made. */
      fields: [{ name: 'start', label: 'Start date', type: 'date', required: false, value: askedStart(q) || nextFirst(),
        note: startNote(q) }],
      go: 'Approve' }, function (v) {
      var start = v && /^\d{4}-\d{2}-\d{2}$/.test(String(v.start || '')) ? v.start : '';
      go.disabled = true;
      ctx.db.rpc('quotation_review', { p_id: q.id, p_ok: true, p_note: null }).then(function (r) {
        var d = r.data || {};
        go.disabled = false;
        if (r.error || d.error) { sheetMsg('qsgReviewMsg', said(r.error || d.error), 'err'); return; }
        window.ADspaceSheet.close();
        RV = null;
        var line = q.ref + ' approved. ' + (d.lines || 0) + ' service line' + (d.lines === 1 ? '' : 's') + ' confirmed. ' + (BILLING_SAID[d.billing] || '') +
          (c.stage && c.stage !== 'active' ? ' Move the client to Active.' : '');
        /* The signed copy is sealed at once (SIGNED DOCUMENT SEAL): drawn
           from the row as it now stands, kept private, never drawn again.
           A seal that fails is said; the next Download seals it. */
        var sealed = function () {
          if (!sealOn()) return Promise.resolve();
          return ctx.db.from('quotations').select(COLS).eq('id', q.id).maybeSingle().then(function (x) {
            if (x.error || !x.data) throw new Error('not-read');
            return sealNow(x.data, ctx);
          }).then(function () { line += ' Signed copy sealed.'; })
            .catch(function () { line += ' The signed copy was not sealed; it is sealed at its next Download.'; });
        };
        var done = function () { sealed().then(function () { (ctx.refresh || ctx.reload)(function () { ctx.msg('qtMsg', line.trim(), 'ok'); }); }); };
        if (!start) { done(); return; }
        ctx.db.rpc('quotation_lines_start', { p_id: q.id, p_start: start }).then(function (r2) {
          var e2 = r2.error || (r2.data && r2.data.error);
          if (e2) line += ' The start date was not saved: ' + said(e2) + ' Set it on each service line.';
          done();
        }).catch(function () { line += ' The start date was not saved. Set it on each service line.'; done(); });
      }).catch(function (e) { go.disabled = false; sheetMsg('qsgReviewMsg', said(e), 'err'); });
    });
  }
  function sendBack() {
    if (!RV) return;
    var q = RV.q, ctx = RV.ctx;
    window.ADspaceConfirm.ask({
      title: 'Send back?', go: 'Send back', wait: true,
      body: (q.submitted_by || 'The colleague who submitted it') + ' will be told, and may correct the details or ask the client to sign again.',
      field: { label: 'Corrections', rows: 3, need: SAID['note-required'] }
    }, function (note) {
      return ctx.db.rpc('quotation_review', { p_id: q.id, p_ok: false, p_note: String(note || '').trim() }).then(function (r) {
        var d = r.data || {};
        if (r.error || d.error) return said(r.error || d.error);
        /* The question shuts first, then the sheet under it. */
        setTimeout(function () {
          window.ADspaceSheet.close();
          RV = null;
          ctx.reload(function () { ctx.msg('qtMsg', q.ref + ' sent back to ' + (q.submitted_by || 'the colleague who submitted it') + '.', 'ok'); });
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
      ctx.reload(function () { ctx.msg('qtMsg', q.ref + ' marked signed. Submit it to a reviewer.', 'ok'); });
    }).catch(function (e) { go.disabled = false; sheetMsg('qsgPaperMsg', said(e), 'err'); });
  }
  /* A quotation's invoices (QUOTATION INVOICES, 2026-11-17; the user: a
     Bukku draft a billing cycle, finance approving it there). One row a
     cycle and kind, from the day the services start, each made by Create in
     Bukku at Clients: Billing Work; the advertising budget its own draft to
     the contact chosen for it, with no tax. */
  var QI = null;
  var QI_SAID = {
    'not-reviewed': 'Approve the signed quotation first.', 'no-start': 'Set the start date first.',
    'not-linked': 'Link this client to Bukku in Billing first.', invoiced: 'This invoice has already been created in Bukku.',
    creating: 'Bukku will finish creating this invoice shortly. Refresh the page in a few minutes.', 'no-budget-account': 'Set the advertising budget account in Settings, Accounting, Bukku.',
    nothing: 'Nothing is billed in this cycle.', 'no-tax-code': 'An item\'s SST has no Bukku tax code. Read the tax codes from Bukku in Settings, Accounting, Tax codes.',
    'no-fx': window.ADspaceWords.line.fxUnset, 'no-sku': 'An item has no SKU on the Rate Card. Add its SKU in Services.',
    'no-product': 'Bukku has no product with that SKU. Add it in Bukku first.', 'no-bukku-account': 'Bukku has no account with that code. Check the code in Settings, Accounting, Bukku.',
    'not-confirmed': 'Bukku did not answer. Check Bukku before creating it again.', removed: 'This quotation has been removed. Restore it first.',
    withdrawn: 'This quotation has been withdrawn. No further invoices can be created from it.',
    'bad-request': 'This invoice could not be read. Refresh the page.'
  };
  function qiSaid(d) {
    var e = d && (d.error || d);
    var k = String((e && e.message) || e || '');
    var w = QI_SAID[k] || said(k);
    if (k === 'no-sku' && d.line) w = d.line + ' has no SKU on the Rate Card. Add its SKU in Services.';
    if (k === 'no-product' && d.sku) w = 'Bukku has no product with SKU ' + d.sku + (d.line ? ' (' + d.line + ')' : '') + '. Add it in Bukku first.';
    if (k === 'invoiced' && d.number) w = 'Invoice ' + d.number + ' has already been created in Bukku.';
    return w;
  }
  function openInvoices(q, ctx, opener) {
    if (!$('qiSheet')) return;
    QI = { q: q, ctx: ctx };
    $('qiFor').textContent = q.ref + ' · ' + q.brand;
    $('qiBody').innerHTML = '';
    sheetMsg('qiMsg', '');
    window.ADspaceSheet.show($('qiSheet'), { opener: opener || null, onClose: function () { QI = null; } });
    loadInvoices();
  }
  function loadInvoices() {
    if (!QI) return;
    var me = QI, q = me.q, ctx = me.ctx;
    window.ADspaceState.skeleton($('qiBody'), 3);
    ctx.db.rpc('quotation_invoices_of', { p_id: q.id }).then(function (r) {
      if (QI !== me) return;
      var d = r.data || {};
      if (r.error) { window.ADspaceState.failLine($('qiBody'), 'The invoices', said(r.error), loadInvoices); return; }
      if (d.error) { $('qiBody').innerHTML = ''; sheetMsg('qiMsg', qiSaid(d), 'err'); return; }
      paintInvoices(d);
    }).catch(function (e) { if (QI === me) window.ADspaceState.failLine($('qiBody'), 'The invoices', said(e), loadInvoices); });
  }
  function qiStart() {
    var me = QI, q = me.q, ctx = me.ctx;
    window.ADspaceConfirm.ask({ title: 'Set start date', go: 'Save', wait: true,
      field: { label: 'Start date', type: 'date', need: 'Choose the start date.', value: askedStart(q) || '', note: startNote(q) }
    }, function (v) {
      return ctx.db.rpc('quotation_lines_start', { p_id: q.id, p_start: String(v || '') }).then(function (r) {
        var e = r.error || (r.data && r.data.error);
        if (e) return said(e);
        if (QI === me) loadInvoices();
        return '';
      }).catch(function (e) { return said(e); });
    });
  }
  function qiDay(v) { return v ? window.ADspaceClock.date(String(v).slice(0, 10)) : ''; }
  function paintInvoices(d) {
    var me = QI, ctx = me.ctx, work = ctx.may('clients.billing', 'work');
    /* The amounts answer at Clients: Billing View alone (2026-11-22): a
       reader at Quotations View meets the cycles and how each stands. */
    var amounts = d.billing !== false;
    var money = function (n) { return d.currency === 'SGD' ? 'S$ ' + rm(n) : 'RM ' + rm(n); };
    var rows = d.rows || [];
    var budget = rows.some(function (x) { return x.kind === 'budget'; });
    var h = '<dl class="ovfacts">' +
      '<dt>Starts</dt><dd>' + (d.start ? esc(qiDay(d.start)) : 'Not set') + '</dd>' +
      '<dt>Months billed</dt><dd>' + esc(String(d.cycles || 1)) + ' month' + (d.cycles === 1 ? '' : 's') + '</dd>' +
      (budget && amounts ? '<dt>Advertising budget</dt><dd>' + esc(d.debtor ? (d.debtor.name || d.debtor.code || 'Chosen contact') : 'Billed to the client') +
        (work ? ' <button class="linkbtn" data-qi="debtor" type="button">Change</button>' : '') + '</dd>' : '') +
      '</dl>';
    /* The start may be set after approval too (quotation_lines_start asks
       an approved quotation): a signed and sealed quotation is never sent
       back for a date (the user, 2026-11-21). */
    if (!d.start) h += '<p class="msg warn qi-note">The start date is not set.' +
      (ctx.may('clients.quotes', 'work') ? ' <button class="btn btn-sm" data-qi="start" type="button">Set start date</button>' : '') + '</p>';
    if (budget && amounts && !d.budget_account) h += '<p class="msg warn qi-note">' + esc(QI_SAID['no-budget-account']) + '</p>';
    if (!rows.length) h += '<p class="emptyline">Nothing to invoice.</p>';
    else h += '<div class="qi-list' + (amounts ? '' : ' is-noamt') + '">' + rows.map(function (x) {
      var made = !!x.number;
      /* A cycle created in Bukku reads Paid or Unpaid once finance has
         approved it there (the nightly copy, `bukku_docs`); until then it
         is still a draft. */
      var st = !made ? (x.creating ? '<span class="chip-state is-warn">Creating</span>' : '<span class="chip-state is-off">Not created</span>')
        : x.paid === true ? '<span class="chip-state is-ok">Paid</span>'
        : x.paid === false ? '<span class="chip-state is-warn">Unpaid</span>'
        : '<span class="chip-state is-off">Draft</span>';
      var when = x.date ? wholeDays(esc(qiDay(x.date) + ' to ' + qiDay(x.until))) : 'Start date not set';
      return '<div class="qi-row" data-cycle="' + x.cycle + '" data-kind="' + esc(x.kind) + '">' +
        '<span class="qi-what"><b>' + (x.kind === 'budget' ? 'Advertising budget' : 'Month ' + x.cycle) + '</b>' +
          '<small>' + when + '</small>' + (made ? '<small class="qi-no">' + esc(x.number) + '</small>' : '') + '</span>' +
        (amounts ? '<span class="qi-amt">' + esc(money(x.amount)) + '</span>' : '') +
        '<span class="qi-state">' + st + '</span>' +
        '<span class="qi-act">' + (!made && work && d.start ? '<button class="btn btn-sm" data-qi="make" type="button">Create in Bukku</button>' : '') + '</span>' +
        '</div>';
    }).join('') + '</div>';
    $('qiBody').innerHTML = h;
  }
  function qiMake(btn) {
    if (!QI) return;
    var me = QI, row = btn.closest('.qi-row');
    btn.disabled = true;
    sheetMsg('qiMsg', '');
    me.ctx.db.functions.invoke('bukku-sync', { body: { action: 'invoicecreate', quotation: me.q.id, cycle: Number(row.getAttribute('data-cycle')), kind: row.getAttribute('data-kind') } })
      .then(function (r) {
        if (QI !== me) return;
        var d = r.data || {};
        if (r.error && !r.data) { btn.disabled = false; sheetMsg('qiMsg', said(r.error), 'err'); return; }
        if (d.error && d.error !== 'in-bukku') { btn.disabled = false; sheetMsg('qiMsg', qiSaid(d), 'err'); return; }
        sheetMsg('qiMsg', d.error === 'in-bukku' ? 'Invoice ' + d.number + ' was already in Bukku. It is now shown here.' : 'Draft ' + (d.made || '') + ' created in Bukku.', 'ok');
        loadInvoices();
      }).catch(function (e) { if (QI === me) { btn.disabled = false; sheetMsg('qiMsg', said(e), 'err'); } });
  }
  /* The contact the advertising budget is invoiced to: a Bukku customer
     found by name, or the client's own contact. */
  function qiDebtor() {
    if (!QI) return;
    var me = QI, ctx = me.ctx;
    window.ADspaceConfirm.ask({ title: 'Bill the advertising budget to', go: 'Find', wait: true,
      fields: [{ name: 'q', label: 'Bukku contact', placeholder: 'Name or Business Registration No.', required: false,
        note: 'Leave empty to bill the client\'s own contact.' }] }, function (v) {
      var term = String(v.q || '').trim();
      if (!term) {
        return ctx.db.rpc('client_ad_debtor_set', { p_client: me.q.client_id, p_contact: null, p_code: null, p_name: null }).then(function (r) {
          var d = r.data || {};
          if (r.error || d.error) return qiSaid(r.error || d);
          loadInvoices();
          return '';
        });
      }
      return ctx.db.functions.invoke('bukku-sync', { body: { action: 'contacts', q: term } }).then(function (r) {
        var d = r.data || {};
        if (r.error && !r.data) return said(r.error);
        if (d.error) return window.ADspaceBukku ? window.ADspaceBukku.said(d) : said(d.error);
        var list = d.contacts || [];
        if (!list.length) return 'No Bukku contact matches. Check the name, or ask an admin who sees every client.';
        setTimeout(function () {
          window.ADspaceConfirm.ask({ title: 'Choose the contact', go: 'Save', wait: true,
            fields: [{ name: 'c', label: 'Bukku contact', choices: list.map(function (c) { return [String(c.id), (c.code ? c.code + ' · ' : '') + c.name]; }), value: String(list[0].id), required: true }] },
            function (w) {
              var c = list.filter(function (x) { return String(x.id) === w.c; })[0];
              if (!c) return 'Choose a contact.';
              return ctx.db.rpc('client_ad_debtor_set', { p_client: me.q.client_id, p_contact: Number(c.id), p_code: c.code || null, p_name: c.name || null }).then(function (r2) {
                var d2 = r2.data || {};
                if (r2.error || d2.error) return qiSaid(r2.error || d2);
                loadInvoices();
                return '';
              });
            });
        }, 0);
        return '';
      });
    });
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
    if ($('qiSheet')) {
      $('qiClose').addEventListener('click', function () { window.ADspaceSheet.close(); QI = null; });
      $('qiBody').addEventListener('click', function (e) {
        var b = e.target.closest('[data-qi]');
        if (!b) return;
        if (b.getAttribute('data-qi') === 'make') qiMake(b);
        else if (b.getAttribute('data-qi') === 'debtor') qiDebtor(b);
        else if (b.getAttribute('data-qi') === 'start') qiStart();
      });
    }
  }

  /* The Overview's section: three rows, read only. */
  function overview(rows, live) {
    var list = (rows || []).filter(function (q) { return !q.removed_at; }).slice(0, 3);
    if (!list.length) return '';
    return '<div class="qt-ov">' + list.map(function (q) {
      var st = stateOf(q, live), h = headline(q);
      return '<div class="qt-ovrow"><span class="svc-name qt-name"><b class="qt-ref">' + window.ADspaceCopy.ref(refOf(q)) + '</b><small>' + esc(metaOf(q)) + '</small></span>' +
        '<span class="qt-ovend"><b>' + esc(h[0]) + '</b><span class="chip-state ' + st[1] + '">' + esc(st[0]) + '</span></span></div>';
    }).join('') + '</div>';
  }

  // ---- Build quote --------------------------------------------------------
  var B = null;   // the sheet's state while open
  /* The Rate Card version named (2026-11-15, the user: "choose which rate
     card"), else the newest, with every version for the choice. */
  function card(ctx, done, version) {
    ctx.db.rpc('rate_card_at', { p_version: version || null }).then(function (r) {
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
  function build(ctx, sel, opener, revises, editing) {
    sel = sel || {};
    /* `editing`: a quotation not yet sent out, saved into itself
       (`quotation_edit`, 2026-11-06). */
    /* The title reads as the button that opened it (Edit, or Adjust and
       send); only its commit says whether it saves or makes the next. */
    $('qbTitle').textContent = editing ? 'Edit ' + editing.ref
      : revises ? (opener && /^Adjust/.test(String(opener.textContent || '').trim()) ? 'Adjust ' : 'Edit ') + revises.ref : 'Build quote';
    $('qbSave').textContent = editing ? 'Save' : 'Create quotation';
    /* `edits`: a line's quantity, rate and months the team typed, by the
       line's key (2026-10-15, the user: "fully customised for the rates qty
       and months"); priced and kept by the database as typed. */
    /* Several brands of the client on one quotation (2026-11-24, the user:
       "1x plan F and 1x plan B for another brand"): each brand's own
       choices kept in `brands`, the board showing one at a time (`bi`). */
    /* BUILD QUOTE ON ONE SHEET (the user, 2026-11-26): every quotation is
       a card a brand, the first named after the client; a quotation kept
       without brands opens as its one card. Each brand keeps its own
       advertising budget ("ad budget per brand"): rows kept on the
       quotation with their brand's place go back to their brand. */
    var brands = Array.isArray(sel.brands) && sel.brands.length ? JSON.parse(JSON.stringify(sel.brands))
      : [Object.assign({ name: ctx.client.name }, pickBrand(sel))];
    if (!brands.some(function (b) { return Array.isArray(b.ads); })) {
      (Array.isArray(sel.ads) ? sel.ads : []).forEach(function (r) {
        var k = Array.isArray(sel.brands) && r.brand != null ? Number(r.brand) : 0, b = brands[k] || brands[0];
        var row = Object.assign({}, r); delete row.brand;
        (b.ads = b.ads || []).push(row);
      });
    }
    var bi = Math.min(Math.max(0, Number(sel._bi) || 0), brands.length - 1);
    var s1 = Object.assign({}, sel, { ads: [] }, brands[bi]);
    B = { ctx: ctx, seq: 0, idem: null, rates: rates(), plan: s1.plan || null, edits: JSON.parse(JSON.stringify(s1.edits || {})), revises: revises || null, editing: editing || null, opener: opener,
      /* The order the team arranged the lines in (2026-11-16), by the lines' keys. */
      order: Array.isArray(s1.order) ? s1.order.slice() : null, brands: brands, bi: bi, open: true };
    /* The tax codes a line may take (2026-10-22), drawn once read. */
    MON.taxCodes().then(function (list) {
      if (!B) return;
      B.codes = list;
      if (B.priced && list.some(function (c) { return c.active; })) $('qbLines').innerHTML = table(B.priced);
    });
    $('qbMsg').textContent = ''; $('qbMsg').className = 'msg';
    $('qbFor').textContent = (ctx.client.client_code ? ctx.client.client_code + ' · ' : '') + ctx.client.name;
    $('qbLines').innerHTML = ''; $('qbSum').textContent = '';
    linesView(false);
    /* The quotation's own date (2026-11-12, the user: a quotation may be
       backdated): today until changed; its reference takes the date's
       month, and it is priced and valid from it. */
    $('qbDate').value = /^\d{4}-\d{2}-\d{2}$/.test(String(sel.date || '')) ? sel.date : window.ADspaceClock.today(); $('qbDate').max = window.ADspaceClock.today();
    $('qbHeading').value = String(sel.title || '');
    $('qbPay').value = String(MON.PAY_DAYS.indexOf(Number(sel.pay)) > -1 ? Number(sel.pay) : 7);
    $('qbValid').value = String(VALID_DAYS.indexOf(Number(sel.valid)) > -1 ? Number(sel.valid) : validDefault());
    advLoad(sel);
    FX = MON.curOf(ctx.client) === 'SG' ? Number(MON.setting('fx_sgd')) || 0 : null;
    CUR = FX == null ? 'RM' : 'S$';
    if (FX === 0) { ctx.msg('qtMsg', SAID['no-fx'], 'err'); B = null; return; }
    /* A build started again, or cancelled, meanwhile: this answer is not
       its (audit 2026-11-24). */
    var mine = B;
    card(ctx, function (c, err) {
      if (B !== mine) return;
      if (!c) { ctx.msg('qtMsg', said(err) || 'No Rate Card version is live.', 'err'); B = null; return; }
      B.card = c;
      /* The version priced on (2026-11-15): the one chosen, else the one
         live on the quotation's Date, which follows the Date until chosen. */
      B.versions = c.versions || [];
      B.cardPicked = Boolean(sel.cardPicked);
      $('qbCard').innerHTML = B.versions.map(function (v, i) {
        return '<option value="' + esc(v.version) + '">v.' + esc(v.version) + ' · ' + (i === 0 ? 'Live' : esc(window.ADspaceClock.date(v.published_at))) + '</option>';
      }).join('') || '<option value="' + esc(c.version) + '">v.' + esc(c.version) + '</option>';
      $('qbCard').value = c.version;
      if (!sel.card && !B.cardPicked) {
        var on = cardOn(qbDay());
        if (on && on !== c.version) { var s0 = Object.assign({}, sel, { card: on }); build(ctx, s0, opener, revises, editing); return; }
      }
      $('qbFor').textContent += ' · priced from v.' + c.version;
      termOptions();
      $('qbTerm').value = String(Number(sel.term) > 1 ? sel.term : 6);
      $('qbTermDisc').checked = sel.term_disc !== false;
      $('qbPeriod').checked = sel.period_total === true;
      discShow();
      /* A new quotation starts with no add-on rate ticked; a reopened one keeps
         what it saved (the user, 2026-11-25). */
      B.aoOn = Array.isArray(sel.addons) ? sel.addons.slice() : [];
      aoPaint();
      /* Add-ons (an outstation fee, a shoot, a revision, files) are one-time
         items too, each under its group on the card (the user, 2026-11-07:
         "couldnt add the outstation fees and add ons"). */
      var addonGroups = [];
      svcs(c, 'addon').forEach(function (s) { var g = (s.spec && s.spec.group) || 'Add-ons'; if (addonGroups.indexOf(g) < 0) addonGroups.push(g); });
      $('qbOnce').innerHTML = ['content', 'verify', 'koc'].concat(addonGroups.map(function (g) { return 'addon:' + g; })).map(function (role) {
        var add = role.indexOf('addon:') === 0, grp = add ? role.slice(6) : '';
        /* Every group under its heading, the first three as the add-ons are
           (2026-11-07). */
        var head = add ? grp : ({ content: 'Content production', verify: 'Verifications', koc: 'KOC packages' })[role];
        var list = add ? svcs(c, 'addon').filter(function (s) { return ((s.spec && s.spec.group) || 'Add-ons') === grp; }) : svcs(c, role);
        list = list.filter(function (s) { return s.rate != null; });
        return (head && list.length ? '<p class="qb-once-h">' + esc(head) + '</p>' : '') + list.map(function (s) {
          /* A stepper a line, as the extra contents are: a count of one-time
             work is pressed up, never typed into a tall box. */
          var id = 'qbO-' + esc(s.slug), nm = esc(s.name);
          return '<div class="qb-step"><button class="iconbtn qb-stepbtn" type="button" data-step="-1" data-for="' + id + '" aria-label="One fewer ' + nm + '">' + MINUS + '</button>' +
            '<input class="qb-stepval" type="number" min="0" max="999" step="1" inputmode="numeric" id="' + id + '" data-slug="' + esc(s.slug) +
            '" value="0" aria-label="' + nm + '">' +
            '<button class="iconbtn qb-stepbtn" type="button" data-step="1" data-for="' + id + '" aria-label="One more ' + nm + '">' + PLUS + '</button>' +
            '<span class="qb-stepname">' + nm + ' <small class="qb-rate">' + CUR + ' ' + esc(rm(cv(s.rate))) + ' each</small></span></div>';
        }).join('');
      }).join('') + '<p class="msg warn" id="qbFilesMsg" role="status" hidden></p>';
      fill(s1);
      if ($('qbBox').hidden) window.ADspaceSheet.show($('qbBox'), { opener: opener || null, onClose: function () { draftKeep(); B = null; } });
      cards(true);
      $('qbBox').querySelector('.sheet-body').scrollTop = 0;
      sidePaint(null);
      preview();
      /* QUOTATION DRAFTS: what the sheet opened with, so a close that
         changed nothing keeps no draft; a draft continued on another
         Rate Card version says so in one line. */
      B.base = sel._base != null ? sel._base : draftCmp(draftOut());
      if (sel._draft && sel._draft !== c.version) {
        $('qbMsg').textContent = 'Repriced on Rate Card v.' + c.version + '. The draft was priced on v.' + sel._draft + '.';
        $('qbMsg').className = 'msg';
      }
      draftOffer(sel._draft != null);
    });
  }

  /* One brand's choices drawn on the board: its plan, content, platforms,
     extra contents, languages, budget, one-time items, line edits, order
     and custom lines (the sheet opening, or another brand chosen). */
  function fill(s) {
    B.plan = s.plan || null;
    B.edits = JSON.parse(JSON.stringify(s.edits || {}));
    B.order = Array.isArray(s.order) ? s.order.slice() : null;
    B.nameKey = null; B.descKey = null;
    var chosen = planOf();
    $('qbAds').value = chosen && chosen.spec.ads ? 'ads' : 'none';
    $('qbAds').dispatchEvent(new Event('input'));
    paintPlans();
    mixFor(Number(s.mix) || 0);
    Array.prototype.forEach.call(document.querySelectorAll('#qbPlats input'), function (i) {
      i.checked = (s.platforms || []).indexOf(i.value) > -1;
    });
    $('qbGraphic').value = String((s.extra || {})[extraSlug('graphic')] || 0);
    $('qbReel').value = String((s.extra || {})[extraSlug('reel')] || 0);
    Array.prototype.forEach.call(document.querySelectorAll('#qbLangs input'), function (i) {
      i.checked = (s.langs || ['en']).indexOf(i.value) > -1;
    });
    $('qbTranslate').checked = Boolean(s.translate);
    budgets(s.budget == null ? 0 : s.budget);
    var once = {};
    (s.once || []).forEach(function (o) { once[o.slug] = o.qty; });
    Array.prototype.forEach.call(document.querySelectorAll('#qbOnce input[data-slug]'), function (i) {
      i.value = String(once[i.getAttribute('data-slug')] || 0);
    });
    onceShow(Boolean((s.once || []).length));
    stepQtys(true);
    B.pkg = (s.packages || []).length ? JSON.parse(JSON.stringify(s.packages[0])) : null;
    if (B.pkg) {
      B.pkg.items = (B.pkg.items || []).map(function (it) { return { slug: it.slug, qty: Number(it.qty) || 1, extra: it.extra != null ? it.extra : null }; });
      B.pkg.incl = B.pkg.incl || [];
    }
    kindShow(s.kind || kindOf(s));
    pkgPaint();
    $('qbCusRows').innerHTML = (s.custom || []).map(cusRow).join('');
    adsLoad(s.ads || []);
    $('qbBrandName').value = s.name || '';
    sync();
  }
  /* What a brand chooses on its own; the rest is the quotation's. */
  var BRAND_KEYS = ['plan', 'mix', 'platforms', 'extra', 'langs', 'translate', 'budget', 'once', 'edits', 'custom', 'order', 'packages', 'ads', 'kind'];
  /* What the page keeps of a brand but never sends with it: its type
     chosen, and its advertising rows, which travel on the quotation with
     the brand's place. */
  function sent(b) {
    var o = Object.assign({}, b);
    delete o.ads; delete o.kind;
    o.name = String(o.name || '').replace(/\s+/g, ' ').trim();
    return o;
  }
  function pickBrand(s) {
    var b = {};
    BRAND_KEYS.forEach(function (k) { if (s[k] !== undefined) b[k] = s[k]; });
    return b;
  }
  /* The board's choices kept with the brand it holds. */
  function keepBrand(s) {
    if (!B || !B.brands || !B.brands[B.bi]) return;
    B.brands[B.bi] = Object.assign({ name: B.brands[B.bi].name || '' }, pickBrand(s));
  }
  function chosen(b) {
    return Boolean(b && (b.plan || (b.platforms || []).length || (b.once || []).length || (b.custom || []).length || (b.packages || []).length ||
      (b.ads || []).length || Number(b.budget) !== 0));
  }
  function fullSel() {
    var s = selection();
    keepBrand(s);
    BRAND_KEYS.forEach(function (k) { delete s[k]; });
    var at = [];
    B.brands.forEach(function (b, i) { if (chosen(b)) at.push(i); });
    /* One card named as the client (or not named) is priced as a quotation
       without brands, as before brands existed. */
    var one = B.brands.length === 1 ? B.brands[0] : null;
    var plain = one && (!String(one.name || '').trim() || String(one.name).replace(/\s+/g, ' ').trim() === String(B.ctx.client.name || '').replace(/\s+/g, ' ').trim());
    if (!at.length || plain) {
      B.sent = null;
      var b = B.brands[plain ? 0 : B.bi], x = sent(b);
      delete x.name;
      Object.assign(s, x);
      if ((b.ads || []).length) s.ads = b.ads.slice();
      return s;
    }
    B.sent = at;
    s.brands = at.map(function (i) { return sent(B.brands[i]); });
    var ads = [];
    at.forEach(function (i, k) { (B.brands[i].ads || []).forEach(function (r) { ads.push(Object.assign({}, r, { brand: k })); }); });
    if (ads.length) s.ads = ads;
    return s;
  }
  function boardAt() { return B && B.sent ? B.sent.indexOf(B.bi) : -1; }
  function brandWord(b) { return String((b && b.name) || '').trim() || 'New brand'; }
  /* The list over the board (the user, 2026-11-24, as mocked up): a row a
     brand, its plan and its figure, Edit and Remove; the board's own row
     marked Editing. */
  function brandMeta(b) {
    var p = b.plan && svcs(B.card, 'plan').filter(function (x) { return x.slug === b.plan; })[0];
    var NAMES = { meta: 'Meta', tiktok: 'TikTok', rednote: 'rednote', linkedin: 'LinkedIn' };
    var pl = (b.platforms || []).map(function (x) { return NAMES[x] || x; });
    var bits = [];
    if ((b.packages || []).length) bits.push(String(b.packages[0].name || 'Package'));
    if (p) bits.push('Plan ' + p.spec.plan);
    if (pl.length) bits.push(pl.length > 1 ? pl.slice(0, -1).join(', ') + ' and ' + pl[pl.length - 1] : pl[0]);
    if (!p && !pl.length && (b.once || []).length) bits.push('Items');
    if (!bits.length && (b.custom || []).length) bits.push('Custom items');
    return bits.join(' · ');
  }
  /* The brands as cards (BUILD QUOTE ON ONE SHEET): a head a brand, its
     type's glyph, its name over what it holds, its figure, the chevron and
     its ⋯ (Duplicate; Remove while two or more stand); the open card holds
     the board (`#qbBoard`), so a brand is changed where it is read. A head
     repaints in place; the cards are drawn again only when they change. */
  var MARK = { plan: 'layers', package: 'box', items: 'file' };
  var CHEV = window.ADspaceIcons.glyph('chevron');
  function brandFig(i) {
    var d = B && B.priced;
    if (!d || !d.totals) return ['—', ''];
    var f = null;
    if (B.sent) { var k = B.sent.indexOf(i); f = k > -1 && d.brands ? d.brands[k] : null; }
    else if (i === B.bi || B.brands.length === 1) f = d.totals;
    var on = MON.sstOf(d.lines, d.totals.sst_pct).on;
    return f && f.month ? [CUR + ' ' + acct(f.month.incl), on ? 'Monthly incl. SST' : 'Monthly']
      : f && f.once ? [CUR + ' ' + acct(f.once.incl), on ? 'One-time incl. SST' : 'One-time total'] : ['—', ''];
  }
  function cardHead(b, i) {
    var I = window.ADspaceIcons, open = B.open && i === B.bi, fig = brandFig(i), meta = brandMeta(b);
    var k = b.kind || kindOf(b), mark = I && I.svg ? I.svg(MARK[k] || 'tag') : '';
    var items = [['dup', 2, 'Duplicate']];
    if (B.brands.length > 1) items.push(['remove', 6, 'Remove']);
    return '<button class="qb-bopen" type="button" aria-expanded="' + open + '" aria-controls="qbBoard">' +
      '<span class="qb-bmark" aria-hidden="true">' + mark + '</span>' +
      '<span class="qb-bwho"><span class="qb-bname">' + esc(brandWord(b)) + '</span>' + (meta ? '<span class="qb-bmeta">' + esc(meta) + '</span>' : '') + '</span>' +
      '<span class="qb-bfig">' + (fig[1] ? esc(fig[0]) + '<small>' + esc(fig[1]) + '</small>' : '') + '</span>' +
      '<span class="qb-bchev">' + CHEV + '</span></button>' +
      '<span class="team-act qb-bact"><button class="kmenu-btn" type="button" aria-label="' + esc('More actions, ' + brandWord(b)) + '" aria-expanded="false">' + DOTS + '</button>' +
      '<div class="kmenu" data-menu hidden>' + items.map(function (x) {
        return '<button class="kmenu-item" data-g="' + x[1] + '" data-a="' + x[0] + '" type="button" role="menuitem">' + esc(x[2]) + '</button>';
      }).join('') + '</div></span>';
  }
  function cards(again) {
    if (!B || !B.brands) return;
    var box = $('qbBrandCards'), board = $('qbBoard');
    var els = box.querySelectorAll('.qb-bcard');
    $('qbBrandsN').textContent = String(B.brands.length);
    if (again || els.length !== B.brands.length) {
      var had = document.activeElement && board.contains(document.activeElement) ? document.activeElement : null;
      $('qbBoardHold').appendChild(board);
      box.innerHTML = B.brands.map(function (b, i) {
        return '<div class="qb-bcard" data-bi="' + i + '"><div class="qb-bhead"></div><div class="qb-bbody"></div></div>';
      }).join('');
      els = box.querySelectorAll('.qb-bcard');
      Array.prototype.forEach.call(els, function (el, i) { el.querySelector('.qb-bhead').innerHTML = cardHead(B.brands[i], i); });
      place();
      if (had && had.isConnected) had.focus({ preventScroll: true });
      return;
    }
    Array.prototype.forEach.call(els, function (el, i) { el.querySelector('.qb-bhead').innerHTML = cardHead(B.brands[i], i); });
    place();
  }
  /* The board stands in the open card, or waits unseen while every card is shut. */
  function place() {
    var els = $('qbBrandCards').querySelectorAll('.qb-bcard'), board = $('qbBoard');
    Array.prototype.forEach.call(els, function (el, i) {
      var open = B.open && i === B.bi;
      el.classList.toggle('is-open', open);
      var body = el.querySelector('.qb-bbody');
      if (open && board.parentNode !== body) body.appendChild(board);
    });
    if (!B.open && board.parentNode !== $('qbBoardHold')) $('qbBoardHold').appendChild(board);
  }
  /* A card opened: the board keeps what it held for its brand, then draws
     the brand pressed. Pressed again, the open card shuts. */
  function boardTo(i) {
    if (!B || !B.brands[i]) return;
    keepBrand(selection());
    if (B.open && i === B.bi) { B.open = false; cards(); return; }
    openCard(i);
  }
  /* The board drawn on a brand already kept. */
  function openCard(i) {
    B.bi = i; B.open = true;
    fill(B.brands[i]);
    cards();
    brandSay('');
    preview();
  }
  /* Add brand: a card that opens ready to fill, its name first. */
  function brandNew(from) {
    if (!B) return;
    keepBrand(selection());
    var b = from != null ? Object.assign(JSON.parse(JSON.stringify(B.brands[from])), { name: '' })
      : { name: '', platforms: [], langs: ['en'], budget: 0, once: [] };
    var at = from != null ? from + 1 : B.brands.length;
    B.brands.splice(at, 0, b);
    B.bi = at; B.open = true;
    fill(b);
    cards(true);
    brandSay('');
    preview();
    var el = $('qbBrandCards').querySelectorAll('.qb-bcard')[at];
    if (el) el.scrollIntoView({ block: 'nearest' });
    $('qbBrandName').focus();
  }
  /* What a brand still needs before Create, else nothing; the first fault
     opens its card. */
  function brandWrong(b) {
    var k = b.kind || kindOf(b);
    if (!k) return 'Choose what to quote.';
    if (B.brands.length > 1 && !String(b.name || '').trim()) return SAID['bad-brands'];
    if (k === 'plan' && !b.plan && !(b.platforms || []).length) return 'Choose a plan.';
    if (k === 'package') {
      var p = (b.packages || [])[0] || {};
      if (!String(p.name || '').trim()) return 'Enter the package name.';
      if (!(p.items || []).length) return 'Add a Rate Card service to the package.';
      if (!/^\d{1,7}(\.\d{1,2})?$/.test(String(p.price || '').replace(/,/g, ''))) return 'Enter the package price.';
    }
    if (k === 'items' && !(b.once || []).length && !(b.custom || []).length) return 'Choose at least one item.';
    return adsWrong(b.ads) || cusWrong(b.custom);
  }
  function brandSay(t) { $('qbMsg').textContent = t || ''; $('qbMsg').className = t ? 'msg err' : 'msg'; }
  /* The field a fault names, on the open card. */
  function brandFocus(w) {
    var f = null;
    if (w === 'Choose what to quote.') f = $('qbTypes').querySelector('[data-kind]');
    else if (w === SAID['bad-brands']) f = $('qbBrandName');
    else if (w === 'Choose a plan.') f = $('qbPlans').querySelector('[data-plan]');
    else if (w === 'Enter the package name.') f = $('qbPkgName');
    else if (w === 'Add a Rate Card service to the package.') f = $('qbPkgAdd');
    else if (w === 'Enter the package price.') f = $('qbPkgPrice');
    else if (w === 'Choose at least one item.') f = $('qbOnce').querySelector('input');
    else f = Array.prototype.filter.call(document.querySelectorAll('#qbAdRows input:not([disabled])'), function (i) { return !Number(String(i.value).replace(/[^0-9.]/g, '')); })[0] ||
      Array.prototype.filter.call(document.querySelectorAll('#qbCusRows .qb-cusname, #qbCusRows .qb-cusqty, #qbCusRows .qb-cusmo:not([disabled])'), function (i) { return !String(i.value).trim() || (!i.classList.contains('qb-cusname') && !Number(i.value)); })[0];
    if (f && f.focus) { f.scrollIntoView({ block: 'center' }); f.focus(); }
  }
  /* Remove takes a brand off the quotation, Undo where it happened puts it
     back in its place; the last brand stands. */
  function brandRemove(i) {
    if (!B || B.brands.length < 2 || !B.brands[i]) return;
    keepBrand(selection());
    var gone = B.brands.splice(i, 1)[0], wasAt = B.bi, wasOpen = B.open;
    if (i === B.bi) { B.bi = Math.min(i, B.brands.length - 1); fill(B.brands[B.bi]); }
    else if (i < B.bi) B.bi--;
    cards(true); preview();
    var undo = function () {
      if (!B) return;
      keepBrand(selection());
      B.brands.splice(i, 0, gone);
      B.bi = wasAt; B.open = wasOpen;
      fill(B.brands[B.bi]);
      cards(true); preview();
    };
    if (window.ADspaceAdmin && window.ADspaceAdmin.undoHere) window.ADspaceAdmin.undoHere(brandWord(gone) + ' removed.', undo, $('qbBrandCards'));
  }
  /* The lines of the board's brand, which the board edits. */
  function boardLines() {
    var all = (B && B.priced && B.priced.lines) || [];
    if (!B || !B.brands || !B.sent) return all;
    var k = boardAt();
    return all.filter(function (l) { return l.brand === k; });
  }
  /* Every brand's items are changed in the one table, at once (the user,
     2026-11-26: "why does it only allow to edit once at a time"): a line's
     edits and order are its own brand's (`k`, its place on the
     quotation), the open card's held on B as the board draws it, every
     other brand's on that brand, all priced again together. */
  function onBoard(k) { return !B.sent || k == null || k === boardAt(); }
  function brandAt(k) { return onBoard(k) ? null : B.brands[B.sent[k]] || null; }
  function editsAt(k) { var b = brandAt(k); return b ? (b.edits || (b.edits = {})) : B.edits; }
  function putEdit(k, key, e) {
    var all = editsAt(k), b = brandAt(k);
    if (Object.keys(e).length) all[key] = e; else delete all[key];
    if (b && !Object.keys(all).length) delete b.edits;
  }
  function linesAt(k) {
    var all = (B && B.priced && B.priced.lines) || [];
    return B && B.sent ? all.filter(function (l) { return l.brand === k; }) : all;
  }
  function setOrder(k, keys) { var b = brandAt(k); if (b) b.order = keys; else B.order = keys; }
  function lineId(k, key) { return (k == null ? '' : k) + '#' + key; }
  function brandOf(el) {
    var r = el.closest('[data-brand]'), v = r ? r.getAttribute('data-brand') : '';
    return v === '' || v == null ? null : Number(v);
  }
  /* A count a stepper holds, for any brand: the open card's is its
     stepper on the board; another brand's is the figure kept on that
     brand (its extra content pieces, its one-time items), so the line and
     the brand's own choice never differ. */
  function stepAt(k, key) {
    var b = brandAt(k);
    if (!b) {
      var el = stepperOf(key);
      return el ? { max: Number(el.max || 999), now: el.value, set: function (n) { el.value = String(n); } } : null;
    }
    var part = String(key || '').split('|'), kind = part[0], slug = part[1] || '';
    if (!slug) return null;
    if (kind === 'extra') {
      var ex = b.plan && (slug === extraSlug('graphic') ? $('qbGraphic') : slug === extraSlug('reel') ? $('qbReel') : null);
      if (!ex) return null;
      return { max: Number(ex.max || 999), now: String((b.extra || {})[slug] || 0),
        set: function (n) { b.extra = Object.assign({}, b.extra); b.extra[slug] = n; } };
    }
    var ob = ['content', 'verify', 'koc', 'kol', 'addon'].indexOf(kind) > -1 ? document.getElementById('qbO-' + slug) : null;
    if (!ob) return null;
    var cur = (b.once || []).filter(function (o) { return o.slug === slug; })[0];
    return { max: Number(ob.max || 999), now: String(cur ? cur.qty : 0), set: function (n) {
      b.once = (b.once || []).filter(function (o) { return o.slug !== slug; });
      if (n > 0) b.once.push({ slug: slug, qty: n });
    } };
  }


  /* The plans of the chosen kind as cards: the letter and its fee over its
     platforms and contents; the one chosen pressed again leaves no plan
     (advertising or one-time items alone). */
  var MINUS = window.ADspaceIcons.glyph('minus');
  var PLUS = window.ADspaceIcons.glyph('plus');
  function paintPlans() {
    var withAds = $('qbAds').value === 'ads';
    var list = svcs(B.card, 'plan').filter(function (p) { return Boolean(p.spec.ads) === withAds; });
    $('qbPlans').innerHTML = list.map(function (p) {
      var on = p.slug === B.plan;
      return '<button class="qb-plan' + (on ? ' is-on' : '') + '" type="button" role="radio" aria-checked="' + on + '" data-plan="' + esc(p.slug) + '">' +
        '<span class="qb-radio" aria-hidden="true"></span><span class="qb-plantext"><b>' + esc(p.spec.plan) + ' · ' + CUR + ' ' + esc(rm(cv(p.rate)).replace(/\.00$/, '')) +
        '</b><small>' + (p.spec.platforms === 1 ? '1 platform' : 'Up to ' + p.spec.platforms + ' platforms') + '</small>' +
        '<small>' + p.spec.contents + ' content pieces: ' + mixWords(p.spec.mix || [], true) + '</small>' +
        (p.spec.ad_budget ? '<small>Advertising budget up to ' + esc(CUR + ' ' + whole(p.spec.ad_budget)) + '</small>' : '') +
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
    adsFollow();
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
    $('qbMixRow').parentNode.classList.toggle('is-bare', $('qbMixRow').hidden);
    $('qbPlatsLabel').textContent = p ? 'Choose platforms (' + p.spec.platforms + ' in the plan)' : 'Choose platforms';
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
  /* The stepper that holds a line's quantity, found by the line's slug
     (its key is kind|slug|label), else none. */
  function stepperOf(key) {
    var part = String(key || '').split('|'), kind = part[0], slug = part[1] || '';
    if (!slug) return null;
    if (kind === 'extra') {
      if (B && B.plan && slug === extraSlug('graphic')) return $('qbGraphic');
      if (B && B.plan && slug === extraSlug('reel')) return $('qbReel');
      return null;
    }
    return ['content', 'verify', 'koc', 'kol', 'addon'].indexOf(kind) > -1 ? document.getElementById('qbO-' + slug) : null;
  }
  /* A line with a stepper takes its count from the stepper alone: a Qty
     typed on it before 2026-11-07 is moved into the stepper as the sheet
     opens, and none is ever sent beside it, so the two never differ
     (Betelnut, 2026-11-07: the stepper read 2, the line kept 1). */
  function stepQtys(move) {
    Object.keys(B.edits || {}).forEach(function (k) {
      var e = B.edits[k], step = e && e.qty != null && stepperOf(k);
      if (!step) return;
      if (move) step.value = String(Math.max(0, Math.floor(Number(e.qty) || 0)));
      delete e.qty;
      if (!Object.keys(e).length) delete B.edits[k];
    });
  }
  /* The date as the sheet stands; today where it holds no day. */
  /* The five terms a quotation is offered on (2026-10-14), each with the
     adjustment in force on the quotation's date, as quote_card prices it
     (2026-11-12: the labels read the published version's 15% after Tax
     and terms set 0%). The version's figure stands in only where the
     settings did not load; 18 months takes 12's where it has none. */
  function termOptions() {
    var set = ((B.card || {}).snapshot || {}).settings || {}, at = qbDay(), was = $('qbTerm').value;
    $('qbTerm').innerHTML = MON.QUOTE_TERMS.map(function (m) {
      var key = MON.termKey(m);
      var own = MON.setting(key, at);
      if (own == null && key === 'term_18_23') own = MON.setting('term_12_23', at);
      var pct = Number((own != null ? own : set[key] != null ? set[key] : key === 'term_18_23' ? set.term_12_23 : 0) || 0);
      return '<option value="' + m + '">' + m + ' months' + (pct ? ' · ' + (pct < 0 ? '−' : '+') + Math.abs(pct) + '%' : '') + '</option>';
    }).join('');
    if (was) $('qbTerm').value = was;
    discShow();
  }
  /* The term discount, the team's choice per quotation (QUOTATION
     PACKAGES, 2026-11-25): offered only where the term has one, ticked
     unless the team unticks it; a surcharge is never a choice. */
  function termPctOf(m) {
    var set = ((B.card || {}).snapshot || {}).settings || {}, key = MON.termKey(m), own = MON.setting(key, qbDay());
    if (own == null && key === 'term_18_23') own = MON.setting('term_12_23', qbDay());
    return Number((own != null ? own : set[key] != null ? set[key] : key === 'term_18_23' ? set.term_12_23 : 0) || 0);
  }
  function discShow() {
    var pct = termPctOf(Number($('qbTerm').value) || 6), once = Boolean(B && B.monthly === false);
    /* The term and its discount are asked only where a line is monthly. */
    $('qbTerm').parentNode.hidden = once;
    $('qbDiscBox').hidden = once || !(pct < 0);
    $('qbDiscPct').textContent = pct < 0 ? '(' + Math.abs(pct) + '% for ' + (Number($('qbTerm').value) || 6) + ' months)' : '';
  }
  /* The advertising budget (2026-11-12, the user): a tick, then a row a
     platform, each Monthly or One-time with its budget and, for Monthly,
     its months; prefilled from the budget chosen above and the term, every
     figure editable. Kept with the quotation, never a service line. */
  var X_ICON = window.ADspaceIcons.glyph('x');
  function adRow(r) {
    r = r || {};
    var opt = function (list, v) {
      return list.map(function (x) { return '<option value="' + esc(x[0]) + '"' + (x[0] === v ? ' selected' : '') + '>' + esc(x[1]) + '</option>'; }).join('');
    };
    var once = r.freq === 'once';
    return '<div class="qb-adrow" data-ad' + (r.auto ? ' data-auto' : '') + '>' +
      '<select class="select qb-adplat" data-nofind aria-label="Platform">' + opt(MON.AD_PLATFORMS, r.platform || 'meta') + '</select>' +
      '<input class="input qb-adbud" type="text" inputmode="decimal" data-noenter data-nodraft aria-label="Budget (' + CUR + ')" placeholder="Budget (' + CUR + ')" value="' + esc(r.budget ? rm(r.budget) : '') + '">' +
      /* Months empty or 0 is One-time (2026-11-12, the user: no extra
         selection for a simple action). */
      '<input class="input qb-admo" type="text" inputmode="numeric" data-noenter data-nodraft aria-label="Months, empty for one-time" placeholder="One-time" value="' + esc(once ? '' : String(r.months || '')) + '">' +
      '<span class="qb-adamt"></span>' +
      '<button class="iconbtn qb-adx" type="button" aria-label="Remove platform">' + X_ICON + '</button></div>';
  }
  function adNum(v) { var n = Number(String(v || '').replace(/[^0-9.]/g, '')); return isFinite(n) ? Math.round(n * 100) / 100 : 0; }
  function adsRead() {
    return Array.prototype.map.call(document.querySelectorAll('#qbAdRows [data-ad]'), function (row) {
      var mo = Math.max(0, Math.floor(Number(row.querySelector('.qb-admo').value) || 0));
      var o = { platform: row.querySelector('.qb-adplat').value, freq: mo ? 'monthly' : 'once', budget: adNum(row.querySelector('.qb-adbud').value) };
      if (mo) o.months = mo;
      return o;
    });
  }
  function adsPaint() {
    var total = 0;
    Array.prototype.forEach.call(document.querySelectorAll('#qbAdRows [data-ad]'), function (row) {
      var mo = row.querySelector('.qb-admo');
      var b = adNum(row.querySelector('.qb-adbud').value), n = Math.max(1, Math.floor(Number(mo.value) || 0));
      total += b * n;
      row.querySelector('.qb-adamt').textContent = b && n ? CUR + ' ' + acct(b * n) : '';
    });
    $('qbAdSum').textContent = total ? 'Advertising budget for the term ' + CUR + ' ' + acct(total) : '';
  }
  function adsLoad(list) {
    list = Array.isArray(list) ? list : [];
    $('qbAdOn').checked = list.length > 0;
    $('qbAdBox').hidden = !list.length;
    adsShow();
    $('qbAdRows').innerHTML = list.map(adRow).join('');
    adsPaint();
  }
  function adsBudget() {
    if (FX != null) return 0;
    var p = planOf(), v = Number($('qbBudget').value);
    return v > 0 ? v : v === 0 && p ? Number(p.spec.ad_budget) || 0 : 0;
  }
  function adsFirst() {
    return { platform: 'meta', freq: 'monthly', budget: adsBudget(), months: Number($('qbTerm').value) || 6, auto: true };
  }
  /* The row Include advertising budget opened follows the budget and the
     term chosen above until a figure in it is typed (2026-11-12, the user:
     "up to 2k … calculate 2k instead of 4k"). */
  function adsFollow() {
    var row = document.querySelector('#qbAdRows [data-ad][data-auto]');
    if (!row) return;
    var b = adsBudget();
    row.querySelector('.qb-adbud').value = b ? rm(b) : '';
    if (Number(row.querySelector('.qb-admo').value) > 0) row.querySelector('.qb-admo').value = String(Number($('qbTerm').value) || 6);
    adsPaint();
  }
  /* What blocks Create: a row with no budget, or Monthly with no months. */
  /* What blocks Create: a row with no budget, or Monthly with no months
     (a brand's rows, else the open card's). */
  function adsWrong(list) {
    var rows = list || ($('qbAdOn').checked ? adsRead() : []);
    if (!list && $('qbAdOn').checked && !rows.length) return 'Add a platform, or remove the advertising budget.';
    if (rows.some(function (r) { return !(r.budget > 0); })) return FX != null ? 'Enter each platform\'s budget in S$.' : 'Enter each platform\'s budget.';
    if (rows.some(function (r) { return r.freq === 'monthly' && !(r.months >= 1 && r.months <= 36); })) return 'Enter each platform\'s months, from 1 to 36.';
    return '';
  }
  function cusRow(r) {
    r = r || {};
    var once = r.basis === 'once';
    return '<div class="qb-cus" data-cus' + (r.renews ? ' data-renews="' + esc(r.renews) + '"' : '') + '>' +
      '<div class="qb-cusrow">' +
      '<input class="input qb-cusname" type="text" data-noenter data-nodraft aria-label="Item" placeholder="Item" maxlength="120" value="' + esc(r.label || '') + '">' +
      '<input class="input qb-cusqty" type="text" inputmode="numeric" data-noenter data-nodraft aria-label="Quantity" placeholder="Qty" value="' + esc(String(r.qty || 1)) + '">' +
      '<input class="input qb-cusrate" type="text" inputmode="decimal" data-noenter data-nodraft aria-label="Rate (' + CUR + ')" placeholder="Rate (' + CUR + ')" value="' + esc(r.rate != null && r.rate !== '' ? rm(r.rate) : '') + '">' +
      '<input class="input qb-cusmo" type="text" inputmode="numeric" data-noenter data-nodraft aria-label="Months, empty for one-time" placeholder="One-time" value="' + esc(once ? '' : String(r.months || '')) + '">' +
      '<input class="input qb-cusstart" type="date" aria-label="Start date" value="' + esc(r.start || '') + '">' +
      '<button class="iconbtn qb-cusx" type="button" aria-label="Remove item">' + X_ICON + '</button></div>' +
      '<textarea class="textarea qb-cusdesc" rows="2" data-nodraft aria-label="Description" placeholder="Description, one point per line">' + esc((r.detail || []).join('\n')) + '</textarea>' +
      (r.renews ? '<span class="qb-cusnote">Renews the confirmed service line</span>' : '') + '</div>';
  }
  function cusRead() {
    return Array.prototype.map.call(document.querySelectorAll('#qbCusRows [data-cus]'), function (box) {
      var mo = Math.max(0, Math.floor(Number(box.querySelector('.qb-cusmo').value) || 0)), basis = mo ? 'month' : 'once';
      var o = { label: box.querySelector('.qb-cusname').value.trim(), qty: Math.max(0, Math.floor(Number(box.querySelector('.qb-cusqty').value) || 0)),
        rate: adNum(box.querySelector('.qb-cusrate').value), basis: basis,
        detail: box.querySelector('.qb-cusdesc').value.split(/\r?\n/).map(function (x) { return x.replace(/^\s*[-•·]\s*/, '').trim(); }).filter(Boolean) };
      if (mo) o.months = mo;
      var st = box.querySelector('.qb-cusstart').value;
      if (/^\d{4}-\d{2}-\d{2}$/.test(st)) o.start = st;
      if (box.getAttribute('data-renews')) o.renews = box.getAttribute('data-renews');
      return o;
    });
  }
  function cusWrong(list) {
    var rows = list || cusRead();
    if (rows.some(function (r) { return !r.label; })) return 'Enter each custom item\'s name.';
    if (rows.some(function (r) { return !(r.qty >= 1); })) return 'Enter each custom item\'s quantity.';
    if (rows.some(function (r) { return r.basis === 'month' && !(r.months >= 1 && r.months <= 36); })) return 'Enter each custom item\'s months, from 1 to 36.';
    return '';
  }
  /* More details (2026-11-24): the title, the Rate Card version, bilingual
     content, custom lines, Bill to and terms in one fold, open where the
     quotation holds any of them. */
  function advLoad(sel) {
    $('qbTerms').value = (sel.terms || []).join('\n');
    $('qbRenewBox').hidden = true; $('qbRenewBox').innerHTML = '';
    B.entity = sel.entity || '';
    $('qbMore').open = Boolean((sel.terms || []).length || sel.title || sel.cardPicked);
    billTo();
  }
  /* Extras: one-time items and the advertising budget open their rows when
     added, their Add buttons standing until then. */
  function onceShow(on) {
    $('qbOnceMore').hidden = !on;
    $('qbOnceAdd').hidden = on;
  }
  function adsShow() { $('qbAdAddFirst').hidden = $('qbAdOn').checked; }
  /* At a desk the item table stands on the sheet under the brands, every
     brand's typed there beside the cards that choose them (the user,
     2026-11-26: "Same sheet at a desk"); the Summary beside it is the
     cart. On a phone View quote turns the sheet to the items, as a cart
     shows what is in it, and Back returns (2026-11-25: "It's like a
     bucket or cart"). The desk is where the Summary is drawn, one media
     line in css/console.css (760). */
  var DESK = window.matchMedia ? window.matchMedia('(min-width: 761px)') : null;
  function desk() { return !!(DESK && DESK.matches); }
  function linesView(on) {
    var card = $('qbBox').querySelector('.sheet-card');
    card.classList.toggle('is-lines', Boolean(on) && !desk());
    viewSay();
    if (on || !desk()) $('qbBox').querySelector('.sheet-body').scrollTop = 0;
  }
  /* View quote is drawn on a phone once an item is priced, with the count
     beside it as a cart's; at a desk the items are already on the sheet. */
  function viewSay() {
    var b = $('qbView');
    if (!B || !b) return;
    var card = $('qbBox').querySelector('.sheet-card');
    if (desk()) card.classList.remove('is-lines');
    var on = card.classList.contains('is-lines');
    var n = ((B.priced && B.priced.lines) || []).length;
    $('qbLinesBox').hidden = desk() ? !n && !B.err : !on;
    b.hidden = desk() || (!n && !on);
    b.setAttribute('aria-expanded', on ? 'true' : 'false');
    /* Preview PDF stands in the foot beside the Summary; on a phone it is
       under the items View quote opens. */
    $('qbPreviewFoot').hidden = !sideOn();
    $('qbPreview').parentNode.hidden = desk();
    b.innerHTML = on ? 'Back' : 'View quote<span class="tab-n">' + n + '</span>';
    b.setAttribute('aria-label', on ? 'Back' : 'View quote, ' + n + (n === 1 ? ' item' : ' items'));
  }
  if (DESK) {
    var deskTurn = function () { if (B && $('qbBox') && !$('qbBox').hidden) viewSay(); };
    if (DESK.addEventListener) DESK.addEventListener('change', deskTurn); else if (DESK.addListener) DESK.addListener(deskTurn);
  }
  /* Bill to: the client's billing entities, the primary first, drawn
     where there are two or more. */
  function billTo() {
    var c = B && B.ctx.client;
    if (!c) return;
    var paint = function (L) {
      if (!B) return;
      $('qbBillBox').hidden = L.length < 2;
      if (L.length < 2) return;
      L = L.slice().sort(function (a, b) { return (b.main ? 1 : 0) - (a.main ? 1 : 0); });
      $('qbBillTo').innerHTML = L.map(function (x) {
        return '<option value="' + esc(x.main ? '' : x.id) + '">' + esc((x.legal_name || 'Billing entity') + (x.main ? ' · Primary' : '')) + '</option>';
      }).join('');
      $('qbBillTo').value = B.entity && L.some(function (x) { return x.id === B.entity && !x.main; }) ? B.entity : '';
    };
    if (B.entities) { paint(B.entities); return; }
    B.ctx.db.rpc('client_entities_list', { p_client: c.id }).then(function (r) {
      var d = r.data || {};
      if (!B) return;
      B.entities = !r.error && !d.error ? (d.entities || []) : [];
      paint(B.entities);
    }).catch(function () { if (B) paint([]); });
  }
  /* Renew lines: the client's confirmed lines, ticked into custom lines
     that confirm the same line for its new term on approval. */
  /* A renewal starts the day after the line's period ends (ADspaceClock's
     periodEnd, one copy; 2026-11-12: 31 Jan for a month rolled to 3 Mar). */
  function renewFrom(day, n) {
    var C = window.ADspaceClock, end = n ? C.periodEnd(day, n) : '';
    return end ? C.addDays(end, 1) : '';
  }
  function renewOpen() {
    var box = $('qbRenewBox'), c = B && B.ctx.client;
    if (!c) return;
    box.hidden = false;
    box.innerHTML = '<p class="qb-cusnote">Loading…</p>';
    B.ctx.db.from('client_services').select('id, label, qty, rate, tenure, start_on, detail, term_adjust, state, archived_at')
      .eq('client_id', c.id).eq('state', 'confirmed').is('archived_at', null).order('created_at')
      .then(function (r) {
        if (!B) return;
        if (r.error) { box.innerHTML = '<p class="msg err">' + esc(said(r.error)) + '</p>'; return; }
        var taken = Array.prototype.map.call(document.querySelectorAll('#qbCusRows [data-renews]'), function (x) { return x.getAttribute('data-renews'); });
        var L = (r.data || []).filter(function (l) { return taken.indexOf(l.id) < 0; });
        B.renewable = L;
        if (!L.length) { box.innerHTML = '<p class="qb-cusnote">No confirmed service lines to renew.</p><div class="qb-renew-foot"><button class="btn btn-quiet btn-sm" type="button" data-a="shut">Close</button></div>'; return; }
        box.innerHTML = L.map(function (l) {
          return '<label class="tickline"><input type="checkbox" value="' + esc(l.id) + '"> <span>' + esc(l.label) + ' <small class="qb-cusnote">' +
            esc(Number(l.qty) + ' × ' + CUR + ' ' + rm(l.rate) + (Number(l.tenure) > 1 ? ' · ' + l.tenure + ' months' : '')) + '</small></span></label>';
        }).join('') + '<div class="qb-renew-foot"><button class="btn btn-quiet btn-sm" type="button" data-a="shut">Cancel</button>' +
          '<button class="btn btn-primary btn-sm" type="button" data-a="renew">Add</button></div>';
      }).catch(function (e) { if (B) box.innerHTML = '<p class="msg err">' + esc(said(e)) + '</p>'; });
  }
  function renewTake() {
    var ids = Array.prototype.map.call(document.querySelectorAll('#qbRenewBox input:checked'), function (i) { return i.value; });
    var term = Number($('qbTerm').value) || 6;
    (B.renewable || []).filter(function (l) { return ids.indexOf(l.id) > -1; }).forEach(function (l) {
      var month = l.term_adjust === true || Number(l.tenure) > 1;
      $('qbCusRows').insertAdjacentHTML('beforeend', cusRow({ label: l.label, qty: l.qty, rate: l.rate, basis: month ? 'month' : 'once',
        months: month ? term : null, start: renewFrom(l.start_on, Number(l.tenure) || 0), renews: l.id,
        detail: String(l.detail || '').split(/\r?\n/).filter(function (x) { return x.trim(); }) }));
    });
    $('qbRenewBox').hidden = true; $('qbRenewBox').innerHTML = '';
    $('qbRenew').focus();
  }
  /* What quote_extras keeps with the quotation, worked here for its
     preview: the same rows, amounts and payment terms. */
  /* Valid for (2026-11-12): the days a quotation stands, chosen in Build
     quote; it opens on the Business setting where that is one of them. */
  var VALID_DAYS = [14, 30, 45, 60, 90];
  /* The days a quotation stands once sent or published: its own Valid
     for, else the Business setting (quotation_release reads the same). */
  function validFor(q) {
    var v = Number(q && q.selection && q.selection.valid);
    if (VALID_DAYS.indexOf(v) > -1) return v;
    return Number(window.ADspaceMoney && window.ADspaceMoney.setting ? window.ADspaceMoney.setting('quote_valid_days') : 30) || 30;
  }
  function validDefault(at) {
    var d = Number(window.ADspaceMoney && window.ADspaceMoney.setting ? window.ADspaceMoney.setting('quote_valid_days', at) : 30) || 30;
    return VALID_DAYS.indexOf(d) > -1 ? d : 30;
  }
  function extras(sel) {
    var rows = (sel.ads || []).map(function (r) {
      var n = r.freq === 'once' ? null : r.months;
      return { platform: r.platform, freq: r.freq, budget: r.budget, months: n, amount: MON.cents(r.budget * (n || 1)) };
    });
    var out = { layout: 2, pay_days: sel.pay || 7, valid_days: sel.valid || validDefault(), ads: rows, terms: sel.terms || [], title: sel.title || null,
      ads_total: MON.cents(rows.reduce(function (a, r) { return a + r.amount; }, 0)) };
    var ent = sel.entity && (B.entities || []).filter(function (x) { return x.id === sel.entity; })[0];
    if (ent) out.bill_to = { entity_id: ent.id, legal_name: ent.legal_name, company_no: ent.company_no, billing_address: ent.billing_address };
    return out;
  }
  /* The version live on a day: the newest published by its end (MYT). */
  function cardOn(day) {
    var end = Date.parse(day + 'T23:59:59+08:00');
    var hit = (B && B.versions || []).filter(function (v) { return Date.parse(v.published_at) <= end; })[0];
    return hit ? hit.version : ((B && B.versions || []).slice(-1)[0] || {}).version;
  }
  /* Build quote drawn again on another version, what is chosen kept. */
  function rebuildOn(version, picked) {
    if (!B) return;
    var s = fullSel();
    s.card = version; s.cardPicked = picked;
    /* The brands all kept, as the page holds them, the open card open. */
    s.brands = JSON.parse(JSON.stringify(B.brands)); s._bi = B.bi; delete s.ads; BRAND_KEYS.forEach(function (k) { delete s[k]; });
    if (B.entity) s.entity = B.entity;
    s._base = B.base;
    build(B.ctx, s, B.opener, B.revises, B.editing);
  }

  /* QUOTATION DRAFTS (2026-11-25, the user): a new quotation closed before
     Create is kept as a draft against the client and the colleague, in the
     database so it follows the colleague to another device (one a client a
     colleague, no number and no PDF; Create clears it). Build quote opened
     again on the same client offers it at the top of step 1. */
  function draftOut() {
    var s = fullSel();
    s.brands = JSON.parse(JSON.stringify(B.brands)); s._bi = B.bi; delete s.ads; BRAND_KEYS.forEach(function (k) { delete s[k]; });
    if (B.entity) s.entity = B.entity;
    s.cardPicked = Boolean(B.cardPicked);
    /* Today's date is the default, so a draft continued tomorrow is dated
       tomorrow; a date typed back is kept. */
    if (s.date === window.ADspaceClock.today()) delete s.date;
    return s;
  }
  function draftCmp(s) { return JSON.stringify(s); }
  function draftKeep() {
    if (!B || B.made || B.editing || B.revises || !B.card || B.base == null) return;
    var s;
    try { s = draftOut(); } catch (e) { return; }
    if (draftCmp(s) === B.base) return;
    var ctx = B.ctx;
    var bad = function (e) { ctx.msg('qtMsg', 'The draft was not saved. ' + said(e), 'err'); };
    ctx.db.rpc('quotation_draft_save', { p_client: ctx.client.id, p_sel: s, p_card: B.card.version }).then(function (r) {
      var e = r.error || (r.data && r.data.error);
      if (e) { bad(e); return; }
      ctx.msg('qtMsg', 'Draft saved.', 'ok');
    }).catch(bad);
  }
  function draftOffer(skip) {
    var box = $('qbDraft'), mine = B;
    if (!box) return;
    box.hidden = true; box.innerHTML = '';
    B.draft = null;
    if (skip || B.editing || B.revises) return;
    B.ctx.db.rpc('quotation_draft_read', { p_client: B.ctx.client.id }).then(function (r) {
      var d = r && r.data && r.data.draft;
      if (B !== mine || !d || !d.selection) return;
      var C = window.ADspaceClock;
      B.draft = d;
      box.innerHTML = '<span>Draft saved ' + esc(C.date(d.saved_at)) + ', ' + esc(C.clock(d.saved_at)) + '</span>' +
        '<span class="draftline-acts"><button class="btn btn-sm" type="button" data-a="discard">Discard</button>' +
        '<button class="btn btn-sm" type="button" data-a="continue">Continue draft</button></span>';
      box.hidden = false;
    }).catch(function () {});
  }
  function draftPress(e) {
    var b = e.target.closest && e.target.closest('button[data-a]');
    if (!b || !B || !B.draft) return;
    var d = B.draft, ctx = B.ctx;
    if (b.getAttribute('data-a') === 'continue') {
      var s = JSON.parse(JSON.stringify(d.selection));
      /* Priced on the version live on its date, unless one was chosen. */
      if (!s.cardPicked) delete s.card;
      s._draft = d.card || '';
      delete s._step;
      build(ctx, s, B.opener);
      return;
    }
    window.ADspaceConfirm.ask({ title: 'Discard draft?', body: 'The draft saved on ' + window.ADspaceClock.date(d.saved_at) + ' will be discarded. This cannot be undone.',
      go: 'Discard', tone: 'danger', wait: true }, function () {
      return ctx.db.rpc('quotation_draft_discard', { p_client: ctx.client.id }).then(function (r) {
        var x = r.error || (r.data && r.data.error);
        if (x) return said(x);
        if (B && B.draft === d) { B.draft = null; $('qbDraft').hidden = true; $('qbDraft').innerHTML = ''; }
        return '';
      });
    });
  }
  function qbDay() {
    var v = $('qbDate') ? $('qbDate').value : '';
    return /^\d{4}-\d{2}-\d{2}$/.test(v) ? v : window.ADspaceClock.today();
  }
  function selection() {
    /* One-time only (2026-11-27): no brand holds a monthly line, so the
       term is 1, as /quote/'s selection() sends it, and the row and the
       PDF read One-time. */
    var sel = { plan: B.plan, term: B.monthly === false ? 1 : Number($('qbTerm').value) || 6, date: qbDay(), card: B.card ? B.card.version : null,
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
    stepQtys(false);
    if (B.kind === 'package' && B.pkg) sel.packages = [pkgOut()];
    if (Object.keys(B.edits).length) sel.edits = JSON.parse(JSON.stringify(B.edits));
    if (!$('qbDiscBox').hidden && !$('qbTermDisc').checked) sel.term_disc = false;
    if ($('qbPeriod').checked) sel.period_total = true;
    /* The add-on rates ticked (QUOTATION ADD-ON RATES): only those the
       colleague ticked, each still on the card; the database keeps those it
       prices. */
    sel.addons = aoAll().filter(function (k) { return (B.aoOn || []).indexOf(k) >= 0; });
    sel.pay = Number($('qbPay').value) || 7;
    sel.valid = Number($('qbValid').value) || validDefault();
    var title = $('qbHeading').value.replace(/\s+/g, ' ').trim();
    if (title) sel.title = title;
    if (B.order && B.order.length) sel.order = B.order.slice();
    if ($('qbAdOn').checked) sel.ads = adsRead();
    if (B.kind) sel.kind = B.kind;
    /* More details' custom lines, Bill to and terms, kept whether or not
       the fold is open. */
    {
      var cus = cusRead();
      if (cus.length) sel.custom = cus;
      if (!$('qbBillBox').hidden && $('qbBillTo').value) sel.entity = $('qbBillTo').value;
      var terms = $('qbTerms').value.split(/\r?\n/).map(function (x) { return x.trim(); }).filter(Boolean);
      if (terms.length) sel.terms = terms;
    }
    return sel;
  }
  /* The rates beside the extras and the translation come from the same
     answer that prices the lines. */
  function hints(d) {
    var x = (d && (B.brands && d.brands ? (d.brands[boardAt()] || {}).extra_rates : d.extra_rates)) || {};
    var gs = extraSlug('graphic'), rs = extraSlug('reel');
    $('qbBox').querySelector('[data-rate-for="qbGraphic"]').textContent = gs && x[gs] != null ? CUR + ' ' + rm(x[gs]) + ' each' : '';
    $('qbBox').querySelector('[data-rate-for="qbReel"]').textContent = rs && x[rs] != null ? CUR + ' ' + rm(x[rs]) + ' each' : '';
    var p = planOf(), tr = svcs(B.card, 'language')[0];
    var n = p ? p.spec.contents + (Number($('qbGraphic').value) || 0) + (Number($('qbReel').value) || 0) : 0;
    var langs = document.querySelectorAll('#qbLangs input:checked').length;
    $('qbTrRate').textContent = p && tr && langs > 1 ? n * (langs - 1) + ' × ' + cv(tr.rate).toLocaleString('en-MY') : '';
    /* The files asked beyond the pieces the selection makes (QUOTE FILES
       CAPPED, 2026-11-25; quote_preview `files_over`, the one count): the
       team is warned, never stopped, since more may be agreed by hand. */
    var fm = $('qbFilesMsg');
    if (fm) {
      var at = d && d.brands ? boardAt() : null;
      var over = ((d && d.files_over) || []).filter(function (o) { return at == null ? o.brand == null : o.brand === at; });
      fm.textContent = over.map(filesWord).join(' ');
      fm.hidden = !over.length;
    }
  }
  function filesWord(o) {
    var unit = o.covers === 'graphic' ? ['graphic', 'graphics'] : o.covers === 'reel' ? ['reel', 'reels'] : ['content piece', 'content pieces'];
    return o.name + (/s$/i.test(o.name) ? ' are' : ' is') + ' requested for ' + o.qty + ' content ' + (o.qty === 1 ? 'piece' : 'pieces') + '. This quotation includes ' +
      (o.cap ? o.cap + ' ' + unit[o.cap === 1 ? 0 : 1] : 'no ' + unit[1]) + '.';
  }
  /* The figures read afresh (another tab saved Tax and terms, or the day
     turned; js/money.js): a build in hand takes the S$ rate in force and
     prices again, so its foot and its lines never keep the old rate
     (2026-11-26, F4). */
  /* Every read of the figures says so (a tab shown again after a minute),
     so only a changed S$ rate or SST reprices, never during a save, and
     the same build keeps its key: a Create that timed out after its row
     was made is never made twice (2026-11-27). */
  function rates() { return String(MON.setting('fx_sgd')) + '|' + String(MON.setting('sst_pct')); }
  document.addEventListener('adspace-settings', function () {
    if (!B || !B.ctx || B.saving) return;
    var now = rates();
    if (now === B.rates) return;
    B.rates = now;
    if (FX != null) { var fx = Number(MON.setting('fx_sgd')) || 0; if (fx > 0) FX = fx; }
    if (B.priced) preview(true);
  });
  var timer = null;
  function preview(keepKey) {
    clearTimeout(timer);
    /* A changed selection is a new quotation: its own key (audit 15, 2026-10-19). */
    if (B) { if (!keepKey) B.idem = null; B.priced = null; $('qbSave').disabled = true; $('qbPreview').disabled = true; $('qbPreviewFoot').disabled = true; }
    timer = setTimeout(function () {
      if (!B) return;
      var seq = ++B.seq;
      B.sel = fullSel();
      B.priced = null;
      $('qbSave').disabled = true;
      $('qbPreview').disabled = true;
      $('qbPreviewFoot').disabled = true;
      $('qbSum').textContent = '';
      /* The client named, so its SST exemption applies (2026-10-15, audit I1). */
      B.ctx.db.rpc('quote_preview', { p_sel: Object.assign({ client: B.ctx.client.id }, B.sel) }).then(function (r) {
        if (!B || seq !== B.seq) return;
        var d = r.data || {};
        hints(d);
        /* A monthly line added to a one-time quotation: priced again on
           the term asked (2026-11-27). */
        if ((d.error || (r.error && r.error.message)) === 'bad-term' && B.monthly === false) { B.monthly = true; discShow(); preview(true); return; }
        if (r.error || d.error) {
          /* Create stays pressable: it names the card's own fault first, else this. */
          B.err = (d.brand != null && B.sent ? brandWord(B.brands[B.sent[d.brand]]) + ': ' : '') + said(r.error || d.error);
          $('qbSave').disabled = false;
          $('qbLines').innerHTML = '<p class="ovnone">' + esc(B.err) + '</p>';
          cards();
          viewSay();
          return;
        }
        /* The term is asked while any brand holds a monthly line; a flip
           prices again with the term it now sends (2026-11-27). */
        var monthly = (d.lines || []).some(function (l) { return l.basis === 'month'; });
        if (monthly !== (B.monthly !== false)) { B.monthly = monthly; discShow(); preview(true); return; }
        B.priced = d; B.err = '';
        /* No monthly line, no period to total: the tick is not drawn. */
        $('qbPeriodBox').hidden = !(d.totals && d.totals.month);
        /* What was typed for a line the selection no longer holds is let go. */
        (B.sent ? B.sent.map(function (bi, k) { return k; }).concat(boardAt() < 0 ? [boardAt()] : []) : [null]).forEach(function (k) {
          var keys = linesAt(k).map(function (l) { return l.key; }), all = editsAt(k);
          Object.keys(all).forEach(function (x) { if (keys.indexOf(x) < 0) delete all[x]; });
          var b = brandAt(k);
          if (b && b.edits && !Object.keys(b.edits).length) delete b.edits;
        });
        $('qbLines').innerHTML = table(d);
        sidePaint(d);
        $('qbSum').textContent = sumOf(d) + (FX == null ? MON.approx(mainOf(d), B.ctx.client) : '') + (B.sent && B.sent.length > 1 ? ' · ' + B.sent.length + ' brands' : '');
        cards();
        viewSay();
        $('qbSave').disabled = false;
        $('qbPreview').disabled = false;
        $('qbPreviewFoot').disabled = false;
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
    if (t.once && !own) out.push(CUR + ' ' + acct(t.once.incl) + ' one-time');
    return out.length ? out.join(' · ') + (MON.sstOf(d.lines, t.sst_pct).on ? ' incl. SST' : '') : '';
  }
  var UP = window.ADspaceIcons.glyph('chevup');
  var DOWN = window.ADspaceIcons.glyph('chevdown');
  /* The lines and the totals as the quotation will keep them. */
  /* A line written in the sheet itself (a custom line in More details, a
     package in its builder) is changed there, never in the lines. */
  function ownLine(l) { return l.kind === 'custom' || l.kind === 'package'; }
  /* The tax codes a line may take, the client's own first (its value
     empty), or null where none is offered or the line is the team's own
     (2026-10-22); one copy for the lines and the Summary's ⋯. */
  function taxOpts(l, t) {
    var codes = (B && B.codes || []).filter(function (c) { return c.active; });
    var ed = B ? editsAt(l.brand)[l.key] : null;
    var cur = (ed && ed.tax) || l.tax_code || '';
    /* The client's SST reads as Bukku's code at its rate, never a
       second option beside that code (2026-11-12). */
    var own = MON.sstApplies(t.sst_pct) ? MON.sstCode(codes, t.sst_pct) : null;
    if (own) codes = codes.filter(function (c) { return c.code !== own.code || c.code === cur; });
    if (!(codes.length + (own ? 1 : 0)) || ownLine(l)) return null;
    /* Each option its full word and its short one: the closed select
       reads the code (SV8), the open list the rate (2026-11-27). */
    var mine = MON.sstApplies(t.sst_pct) ? 'SST ' + t.sst_pct + '%' : MON.SST_NONE;
    return { cur: cur, opts: [['', own ? own.code + ' · ' + t.sst_pct + '%' : mine, own ? own.code : mine]]
      .concat(codes.map(function (c) { return [c.code, MON.taxCodeWord(c), c.code]; })) };
  }
  function taxWord(sel, full) {
    Array.prototype.forEach.call(sel.options, function (o) { o.textContent = o.getAttribute(full ? 'data-full' : 'data-short'); });
  }
  /* The totals as the quotation reads them, [label, figure, is total, key]
     (ADspaceMoney.quoteRows, one copy, QT-4). */
  /* The totals as a list; the whole period's note a line under it. */
  function totDl(tot, cls, noteCls) {
    var note = tot.filter(function (x) { return x[3] === 'periodNote'; })[0];
    return '<dl class="' + cls + '">' + tot.filter(function (x) { return x !== note; }).map(function (x) {
      return '<div' + (x[2] ? ' class="is-total' + (x[3] === 'periodAll' ? ' is-all' : '') + '"' : '') + '><dt>' + esc(x[0]) + '</dt><dd>' + esc(x[1]) + '</dd></div>';
    }).join('') + '</dl>' + (note ? '<p class="' + noteCls + '">' + esc(note[0]) + '</p>' : '');
  }
  function totRows(d) {
    var t = d.totals || {}, rows = d.lines || [];
    var taxed = MON.sstOf(rows, t.sst_pct), sstOn = taxed.on, incl = sstOn ? ' incl. SST' : '';
    var WORD = { monthSub: 'Monthly subtotal', onceSub: 'One-time subtotal', firstExcl: 'First month excl. SST', monthExcl: 'Monthly excl. SST',
      sst: taxed.word, first: 'First month' + incl, monthly: 'Monthly' + incl, oneOff: sstOn ? 'One-time incl. SST' : 'One-time total',
      term: MON.termLine(t.term, t.term_pct) };
    /* Monthly excl. SST is left out where it equals the subtotal (2026-11-26). */
    var all = MON.quoteRows(t, rows, sstOn), sub = all.filter(function (x) { return x[0] === 'monthSub'; })[0];
    all = all.filter(function (x) { return !(x[0] === 'monthExcl' && sub && Number(sub[1]) === Number(x[1])); });
    /* The whole period's totals where ticked (PERIOD TOTAL ON A QUOTATION,
       2026-11-27), as the quotation prints them. */
    var pt = MON.periodTotals(t, B && B.sel), L = window.ADspaceWords.line, out = [];
    all.forEach(function (x) {
      out.push([x[3] ? x[3].replace(/^./, function (c) { return c.toUpperCase(); }) : WORD[x[0]], (x[2] ? CUR + ' ' : '') + acct(x[1]), x[2], x[0]]);
      if (pt && (x[0] === 'monthly' || x[0] === 'first')) out.push([L.periodTotal(pt.months, sstOn), CUR + ' ' + acct(pt.period), 0, 'period']);
    });
    if (pt && pt.total != null) out.push([L.periodAll(sstOn), CUR + ' ' + acct(pt.total), 1, 'periodAll'], [L.periodNote(pt.months), '', 0, 'periodNote']);
    return out;
  }
  function table(d) {
    var t = d.totals || {}, rows = d.lines || [];
    /* The head holds a cell for the Tax cell where the lines carry one, so
       its cells stand over the lines' (2026-10-31). */
    var hasTax = (B && B.codes || []).some(function (c) { return c.active; });
    var hasPlan = rows.some(function (l) { return l.kind === 'plan'; });
    var mixedPct = (t.term_rows || []).length > 1;
    /* Several brands (2026-11-24): each brand's lines under its name,
       every brand's changed here at once (2026-11-26). */
    var names = (B && B.sent ? B.sent.map(function (i) { return B.brands[i]; }) : null) || t.brands || null, many = Boolean(names && names.length > 1 && rows.some(function (l) { return l.brand != null; }));
    var lastBrand = null;
    var out = '<div class="crm-table qb-table"><div class="crm-head svc-row qb-row"><span class="qb-name">Item</span>' + (hasTax ? '<span class="qb-taxc">Tax</span>' : '') + '<span class="svc-rate qb-qty">Qty</span>' +
      '<span class="svc-rate qb-rate">Rate (' + CUR + ')</span><span class="svc-rate qb-mo">Months</span><span class="svc-rate qb-amt">Subtotal (' + CUR + ')</span></div>' +
      rows.map(function (l) {
        var bk = l.brand == null ? '' : String(l.brand), id = lineId(l.brand, l.key);
        var bhead = '';
        if (many && l.brand !== lastBrand) { lastBrand = l.brand; bhead = '<div class="qb-brandh">' + esc(brandWord(names[l.brand])) + '</div>'; }
        /* Quantity, rate and months are typed where they are read; a line
           quoted off the card names the card's rate under it. */
        var sub = [];
        if (l.list_rate != null) sub.push('Rate Card ' + CUR + ' ' + rm(l.list_rate));
        /* Each line its own term percentage (2026-11-15), said where the
           lines differ. */
        if (l.basis === 'month' && mixedPct && l.pct != null) sub.push(Number(l.pct) ? MON.termLine(l.months, l.pct).replace(/^./, function (c) { return c.toUpperCase(); }) : 'No term adjustment');
        /* The line's tax code (2026-10-22): the client's SST, or one the team
           bills with, chosen where it is read; drawn while any is offered.
           The client's own reads as the rate alone (SST 8%), the codes by
           their code, so on a phone it shares the line with Qty, Rate and
           Months (2026-10-31). */
        var tx = taxOpts(l, t);
        var tax = tx ? '<select class="select select-sm qb-tax" data-nofind data-key="' + esc(l.key || '') + '" aria-label="' + esc('Tax, ' + l.label) + '">' +
          tx.opts.map(function (o) { return '<option value="' + esc(o[0]) + '" data-full="' + esc(o[1]) + '" data-short="' + esc(o[2]) + '"' + (o[0] && o[0] === tx.cur ? ' selected' : '') + '>' + esc(o[2]) + '</option>'; }).join('') +
          '</select>' : '';
        /* A Rate Card one-time item takes Months too (2026-11-12, the user):
           a number bills it monthly, empty or 0 keeps it one-time. */
        var flex = !ownLine(l) && (l.basis === 'once' || l.was_once);
        var box = function (what, v, cls, mode, label) {
          /* A custom line is changed in Advanced, where it is typed. */
          if (ownLine(l)) return '<span class="qb-fixed">' + esc(what === 'rate' ? v : String(v)) + '</span>';
          return '<input class="input input-sm qb-val ' + cls + '" type="text" inputmode="' + mode + '" data-noenter data-nodraft data-key="' +
            esc(l.key || '') + '" data-what="' + what + '" value="' + esc(v) + '" aria-label="' + esc(label + ', ' + l.label) + '">';
        };
        /* The line's inclusions a point each, as the quotation prints them
           (2026-11-04). */
        var incl = (l.kind === 'package' ? MON.planFold([l], t.currency)[0].detail : (l.detail || [])).map(function (x) { return String(x == null ? '' : x).replace(/^\s*[-•·]\s*/, '').trim(); }).filter(Boolean);
        /* Include in plan (the user, 2026-11-06, option A): a line at RM 0
           beside a plan is listed under the plan's inclusions on the
           quotation, not as a row of its own; on unless unticked. */
        var fold = hasPlan && l.kind !== 'plan' && l.basis === 'month' && Number(l.rate) === 0 ?
          '<label class="tickline qb-inplan"><input type="checkbox" data-key="' + esc(l.key || '') + '"' + (l.in_plan ? ' checked' : '') + '> Include in plan</label>' : '';
        /* The description is the Rate Card's until the team changes it for
           this quotation (2026-11-13, the user: "shouldnt be dead end when
           inside admin"); the card itself changes only when it is
           published. A custom line is written in Advanced. */
        var le = B ? editsAt(l.brand)[l.key] : null;
        var own = !!(le && (le.detail || le.name));
        /* Changed from the Rate Card for this quotation (2026-11-16): its
           name, its description or its rate, said once on the line. */
        var edited = !ownLine(l) && (l.list_label != null || l.list_detail != null || l.list_rate != null);
        var grp = B && B.sent ? rows.filter(function (x) { return x.brand === l.brand; }) : rows;
        var at = grp.indexOf(l);
        var move = B ? '<button type="button" class="iconbtn qb-move" data-move="-1" data-key="' + esc(l.key || '') + '" aria-label="' + esc('Move up, ' + l.label) + '"' + (at === 0 ? ' disabled' : '') + '>' + UP + '</button>' +
          '<button type="button" class="iconbtn qb-move" data-move="1" data-key="' + esc(l.key || '') + '" aria-label="' + esc('Move down, ' + l.label) + '"' + (at === grp.length - 1 ? ' disabled' : '') + '>' + DOWN + '</button>' : '';
        var desc = '';
        if (!ownLine(l) && B) {
          desc = '<div class="qb-incl" data-key="' + esc(l.key || '') + '">' +
            (B.descKey === id ?
              '<textarea class="textarea qb-desc" rows="' + Math.max(2, incl.length) + '" data-nodraft aria-label="' + esc('Description, ' + l.label) + '" placeholder="One point per line">' + esc(incl.join('\n')) + '</textarea>' +
              '<div class="qb-desc-acts"><button type="button" class="btn btn-quiet btn-sm qb-desc-cancel">Cancel</button><button type="button" class="btn btn-sm qb-desc-done">Done</button></div>' :
              (incl.length ? '<ul class="incl">' + incl.map(function (x) { return '<li>' + esc(x) + '</li>'; }).join('') + '</ul>' : '') +
              '<div class="qb-desc-acts">' + (edited ? '<span class="qb-desc-own">Changed</span>' : '') +
                '<button type="button" class="btn btn-sm qb-name-edit">' + (window.ADspaceActs ? window.ADspaceActs.glyph('pen') : '') + 'Rename</button>' +
                '<button type="button" class="btn btn-sm qb-desc-edit">' + (window.ADspaceActs ? window.ADspaceActs.glyph(incl.length ? 'pen' : 'plus') : '') + (incl.length ? 'Edit description' : 'Add description') + '</button>' +
                (own ? '<button type="button" class="btn btn-sm qb-desc-card">Use Rate Card</button>' : '') + '<span class="qb-moves">' + move + '</span></div>') +
            '</div>';
        } else {
          desc = '<div class="qb-incl" data-key="' + esc(l.key || '') + '">' +
            (incl.length ? '<ul class="incl">' + incl.map(function (x) { return '<li>' + esc(x) + '</li>'; }).join('') + '</ul>' : '') +
            (B ? '<div class="qb-desc-acts"><span class="qb-moves">' + move + '</span></div>' : '') + '</div>';
        }
        /* The line's name, changed for this quotation where it is read. */
        var naming = B && B.nameKey === id && !ownLine(l);
        var nameCell = naming ?
          '<input class="input input-sm qb-name-in" type="text" maxlength="120" data-noenter data-nodraft data-key="' + esc(l.key || '') + '" value="' + esc(l.label) + '" aria-label="Name">' +
          '<span class="qb-desc-acts"><button type="button" class="btn btn-quiet btn-sm qb-name-cancel" data-key="' + esc(l.key || '') + '">Cancel</button><button type="button" class="btn btn-sm qb-name-done" data-key="' + esc(l.key || '') + '">Done</button></span>' :
          esc(l.label);
        if (l.list_label != null) sub.unshift('Rate Card: ' + l.list_label);
        return bhead + '<div class="svc-row qb-row" data-brand="' + esc(bk) + '"><span class="svc-name qb-name">' + nameCell + (sub.length ? '<small>' + esc(sub.join(' · ')) + '</small>' : '') + fold + '</span>' +
          desc +
          /* A Rate Card one-time item may be billed Monthly (2026-11-12, the
             user): its frequency beside its tax, the months then in its
             Months cell. */
          /* The head names Tax while any code is offered, so every line
             holds the cell, empty where no select applies (a custom line):
             a column on every row (2026-11-25). */
          (tax ? '<span class="qb-taxc"><span class="qb-lab">Tax</span>' + tax + '</span>' : hasTax ? '<span class="qb-taxc"></span>' : '') +
          '<span class="svc-rate qb-qty"><span class="qb-lab">Qty</span>' + box('qty', l.qty, 'qb-qtyval', 'numeric', 'Quantity') + '</span>' +
          '<span class="svc-rate qb-rate"><span class="qb-lab">Rate (' + CUR + ')</span>' + box('rate', rm(l.rate), 'qb-rateval', 'decimal', 'Rate (' + CUR + ')') + '</span>' +
          '<span class="svc-rate qb-mo"><span class="qb-lab">' + (l.basis === 'month' || flex ? 'Months' : '&nbsp;') + '</span>' +
            (l.basis === 'month' ? box('months', l.months || (d.totals || {}).term, 'qb-moval' + (flex ? ' qb-flex' : ''), 'numeric', 'Months') :
              flex ? box('months', '', 'qb-moval qb-flex', 'numeric', 'Months, empty for one-time').replace('value=""', 'value="" placeholder="One-time"') :
              '<span class="qb-once">One-time</span>') + '</span>' +
          '<span class="svc-rate qb-amt">' + esc(l.in_plan ? 'In plan' : rm(l.amount)) + '</span></div>';
      }).join('') + '</div>';
    /* SST said as the Letter of Offer says it (ADspaceMoney.sstApplies);
       the rows are ADspaceMoney.quoteRows', one copy (QT-4). */
    var tot = totRows(d);
    out += totDl(tot, 'qb-tot', 'qb-note');
    var notes = [];
    /* Said as the quotation says it (2026-11-27, How ad spend works). */
    if (t.budget > 0) notes.push('The advertising budget of up to ' + CUR + ' ' + whole(t.budget) + ' per month is not included in this quotation.');
    if ((d.on_request || []).length) notes.push('On request: ' + d.on_request.map(function (x) { return x === 'budget' ? 'advertising budget above ' + CUR + ' ' + whole(topBudget()) : x; }).join(', ') + '.');
    if (notes.length) out += '<p class="qb-note">' + esc(notes.join(' ')) + '</p>';
    return out;
  }

  /* The quotation just made is marked where it lands and its Preview PDF
     takes focus (its Download is in the ⋯ since 2026-11-13), the mark leaving after the Undo bar's time (2026-10-22,
     QT-2). */
  var NEW_MS = 8000;
  function markNew(ref) {
    var row = Array.prototype.filter.call(document.querySelectorAll('.qt-row[data-id]'), function (x) {
      var r = x.querySelector('.qt-ref'); return r && r.textContent === ref;
    })[0];
    if (!row) return;
    row.classList.add('is-new');
    var dl = row.querySelector('.qt-dl [data-a="view"]');
    if (dl) dl.focus({ preventScroll: false });
    setTimeout(function () { row.classList.remove('is-new'); }, NEW_MS);
  }
  // ---- A BRAND'S TYPE (2026-11-25; on one sheet since 2026-11-26) ------------
  /* What a brand's choices are for: a package, a plan (or platforms and a
     budget with none, as before), else items alone. */
  function kindOf(s) {
    s = s || {};
    if ((s.packages || []).length) return 'package';
    if (s.plan || (s.platforms || []).length || Number(s.budget) > 0) return 'plan';
    if ((s.once || []).length || (s.custom || []).length) return 'items';
    return null;
  }
  function kindShow(k) {
    B.kind = k || null;
    var cardEl = $('qbBox').querySelector('.sheet-card');
    cardEl.setAttribute('data-kind', B.kind || '');
    Array.prototype.forEach.call($('qbTypes').querySelectorAll('[data-kind]'), function (t) {
      t.setAttribute('aria-checked', t.getAttribute('data-kind') === B.kind ? 'true' : 'false');
    });
    /* Items are the one-time lines themselves; otherwise they are extras. */
    var box = $('qbOnceMore');
    if (B.kind === 'items') { $('qbItemsSlot').appendChild(box); onceShow(true); }
    else if (box.parentNode === $('qbItemsSlot')) {
      $('qbOnceAdd').parentNode.parentNode.insertBefore(box, $('qbOnceAdd').parentNode.nextSibling);
      onceShow(Array.prototype.some.call(document.querySelectorAll('#qbOnce input[data-slug]'), function (i) { return Number(i.value) > 0; }));
    }
  }
  /* A brand chooses one type: changing it lets go of the other type's choices. */
  function kindPick(k) {
    if (!B || k === B.kind) return;
    if (k !== 'plan') {
      B.plan = null;
      Array.prototype.forEach.call(document.querySelectorAll('#qbPlats input'), function (i) { i.checked = false; });
      $('qbGraphic').value = '0'; $('qbReel').value = '0';
      budgets(0); paintPlans(); mixFor(0);
    }
    if (k !== 'package') B.pkg = null;
    else if (!B.pkg) B.pkg = { name: '', basis: 'month', price: '', items: [], incl: [] };
    kindShow(k);
    pkgPaint();
    sync();
    keepBrand(selection());
    cards();
    preview();
  }
  /* What is missing on a step, else nothing. */


  /* The package on the board: its Rate Card lines, price, inclusions and
     the rate for one more piece, as `p_sel.packages` holds it. */
  function pkgSvc(slug) { return ((B && B.card && B.card.snapshot && B.card.snapshot.services) || []).filter(function (s) { return s.slug === slug && s.active !== false; })[0]; }
  function pkgOut() {
    var k = B.pkg;
    var out = { name: String(k.name || '').replace(/\s+/g, ' ').trim(), basis: k.basis === 'once' ? 'once' : 'month',
      price: String(k.price || '').replace(/,/g, '').trim(),
      items: k.items.map(function (it) { var o = { slug: it.slug, qty: Math.max(1, Number(it.qty) || 1) }; if (it.extra != null && it.extra !== '') o.extra = String(it.extra).replace(/,/g, ''); return o; }),
      incl: (k.incl || []).filter(function (x) { return String(x.text || '').trim(); }).map(function (x) { return { text: String(x.text).trim(), on: Boolean(x.on) }; }) };
    return out;
  }
  function pkgPaint() {
    if (!B || !B.card) return;
    var k = B.pkg || { name: '', basis: 'month', price: '', items: [], incl: [] };
    $('qbPkgName').value = k.name || '';
    $('qbPkgBasis').value = k.basis === 'once' ? 'once' : 'month';
    $('qbPkgBasis').dispatchEvent(new Event('input'));
    $('qbPkgPrice').value = k.price || '';
    var list = 0;
    $('qbPkgRows').innerHTML = (k.items.length ? '<div class="qb-pkgrow qb-pkghd" aria-hidden="true"><span>Service</span><span>Quantity</span><span class="qb-fig">Rate</span><span class="qb-fig">Amount</span><span></span></div>' : '') +
      k.items.map(function (it) {
        var s = pkgSvc(it.slug) || { name: it.slug, rate: 0 }, r = cv(s.rate || 0), id = 'qbPk-' + esc(it.slug), nm = esc(s.name);
        list += r * (Number(it.qty) || 0);
        return '<div class="qb-pkgrow" data-pk="' + esc(it.slug) + '"><span class="qb-pkgname">' + nm + '</span>' +
          '<div class="qb-step"><button class="iconbtn qb-stepbtn" type="button" data-step="-1" data-for="' + id + '" aria-label="One fewer ' + nm + '">' + MINUS + '</button>' +
          '<input class="qb-stepval" type="number" min="1" max="999" step="1" inputmode="numeric" id="' + id + '" value="' + esc(it.qty) + '" aria-label="' + nm + '">' +
          '<button class="iconbtn qb-stepbtn" type="button" data-step="1" data-for="' + id + '" aria-label="One more ' + nm + '">' + PLUS + '</button></div>' +
          '<span class="qb-fig qb-rate">' + esc(rm(r)) + '</span><span class="qb-fig">' + esc(rm(r * (Number(it.qty) || 0))) + '</span>' +
          '<button class="iconbtn qb-pkgx" type="button" aria-label="Remove ' + nm + '">' + X_ICON + '</button></div>';
      }).join('');
    var taken = k.items.map(function (it) { return it.slug; });
    $('qbPkgAdd').innerHTML = '<option value="">Choose a service</option>' + ((B.card.snapshot || {}).services || []).filter(function (s) {
      return s.active !== false && s.rate != null && !(s.spec && s.spec.role === 'plan') && taken.indexOf(s.slug) < 0;
    }).map(function (s) { return '<option value="' + esc(s.slug) + '">' + esc(s.name) + '</option>'; }).join('');
    var price = Number(String(k.price || '').replace(/,/g, ''));
    $('qbPkgList').textContent = k.items.length ? CUR + ' ' + rm(list) : '—';
    $('qbPkgOff').textContent = k.items.length && k.price !== '' && isFinite(price) && list > price
      ? CUR + ' ' + rm(list - price) + ' (' + (Math.round((list - price) / list * 1000) / 10) + '%)' : '—';
    $('qbPkgIncl').innerHTML = (k.incl || []).map(function (x, i) {
      return '<div class="qb-pkgline" data-in="' + i + '"><label class="tickline"><input type="checkbox"' + (x.on ? ' checked' : '') + ' aria-label="Included"></label>' +
        '<input class="input" type="text" maxlength="300" data-noenter data-nodraft value="' + esc(x.text || '') + '" aria-label="Inclusion ' + (i + 1) + '">' +
        '<button class="iconbtn qb-pkgx" type="button" aria-label="Remove inclusion">' + X_ICON + '</button></div>';
    }).join('');
    /* The rate for one more piece in the same month: a content piece's,
       prefilled from the card, the team's where typed (step 3). */
    var contentItems = k.items.filter(function (it) { var s = pkgSvc(it.slug); return s && s.spec && s.spec.role === 'content'; });
    $('qbPkgExtraBox').hidden = !contentItems.length;
    $('qbPkgExtra').innerHTML = contentItems.map(function (it) {
      var s = pkgSvc(it.slug), id = 'qbPx-' + esc(it.slug);
      return '<div><label class="field-label" for="' + id + '">' + esc(s.name) + '</label>' +
        '<input class="input" type="text" inputmode="decimal" id="' + id + '" data-px="' + esc(it.slug) + '" data-noenter data-nodraft value="' + esc(it.extra != null ? it.extra : rm(cv(s.rate))) + '"></div>';
    }).join('');
    aoPaint();
  }
  /* Add-on rates (QUOTATION ADD-ON RATES, 2026-11-25): a tick a package's
     rate for one more piece and a tick a Rate Card add-on, all ticked by
     default; the PDF and the quotation link print the ticked ones. */
  function aoAll() {
    if (!B || !B.card) return [];
    return svcs(B.card, 'content').map(function (s) { return 'extra:' + s.slug; })
      .concat(svcs(B.card, 'addon').filter(function (s) { return s.rate != null; }).map(function (s) { return s.slug; }));
  }
  function aoPaint() {
    var box = $('qbAddons');
    if (!box || !B || !B.card) return;
    B.aoOn = B.aoOn || [];
    var W = window.ADspaceWords.line, rows = [], at = {};
    var put = function (g, key, name, hint) { if (!at[g]) { at[g] = []; rows.push([g, at[g]]); } at[g].push([key, name, hint]); };
    if (B.kind === 'package' && B.pkg) B.pkg.items.forEach(function (it) {
      var s = pkgSvc(it.slug);
      if (s && s.spec && s.spec.role === 'content') put(W.addonExtra, 'extra:' + s.slug, s.name, '');
    });
    svcs(B.card, 'addon').forEach(function (s) {
      if (s.rate == null) return;
      put((s.spec && s.spec.group) || W.addons, s.slug, s.name, MON.addonRate({ rate: cv(s.rate), unit: s.unit }, CUR === 'S$' ? 'SGD' : 'MYR'));
    });
    $('qbAddonBox').hidden = !rows.length;
    box.innerHTML = rows.map(function (r) {
      return '<div class="qb-aogroup"><span class="field-label">' + esc(r[0]) + '</span>' + r[1].map(function (x) {
        return '<label class="tickline"><input type="checkbox" data-ao="' + esc(x[0]) + '"' + (B.aoOn.indexOf(x[0]) >= 0 ? ' checked' : '') + '>' +
          '<span>' + esc(x[1]) + (x[2] ? '<span class="qb-aorate">' + esc(x[2]) + '</span>' : '') + '</span></label>';
      }).join('') + '</div>';
    }).join('');
  }
  /* The package as typed, read back into the board. */
  function pkgRead() {
    if (!B || !B.pkg) return;
    var k = B.pkg;
    k.name = $('qbPkgName').value;
    k.basis = $('qbPkgBasis').value;
    k.price = $('qbPkgPrice').value;
    k.items.forEach(function (it) {
      var q = document.getElementById('qbPk-' + it.slug), x = document.getElementById('qbPx-' + it.slug);
      if (q) it.qty = Math.min(999, Math.max(1, Math.floor(Number(q.value) || 1)));
      if (x) { var s = pkgSvc(it.slug); it.extra = s && String(x.value).replace(/,/g, '') === String(rm(cv(s.rate))).replace(/,/g, '') ? null : x.value; }
    });
    k.incl = Array.prototype.map.call($('qbPkgIncl').querySelectorAll('[data-in]'), function (r) {
      return { text: r.querySelector('input[type="text"]').value, on: r.querySelector('input[type="checkbox"]').checked };
    });
  }

  /* The figures under the contents, followed as the quantities and the
     price are typed, the rows kept where they are. */
  function pkgFigs() {
    if (!B || !B.pkg) return;
    var k = B.pkg, list = 0;
    k.items.forEach(function (it) {
      var s = pkgSvc(it.slug), r = cv((s && s.rate) || 0), row = $('qbPkgRows').querySelector('[data-pk="' + it.slug + '"]');
      list += r * it.qty;
      var q = document.getElementById('qbPk-' + it.slug);
      if (q && Number(q.value) !== it.qty && document.activeElement !== q) q.value = String(it.qty);
      if (row) row.lastElementChild.previousElementSibling.textContent = rm(r * it.qty);
    });
    var price = Number(String(k.price || '').replace(/,/g, ''));
    $('qbPkgList').textContent = k.items.length ? CUR + ' ' + rm(list) : '—';
    $('qbPkgOff').textContent = k.items.length && String(k.price || '').trim() !== '' && isFinite(price) && list > price
      ? CUR + ' ' + rm(list - price) + ' (' + (Math.round((list - price) / list * 1000) / 10) + '%)' : '—';
  }
  /* The summary beside the steps at a desk: the board's lines, then the
     figure the person is choosing towards. */
  /* The Summary is the cart at a desk (the user, 2026-11-25): every
     priced line under Monthly, One-time and Advertising budget, each
     group's subtotal, then the totals as the quotation reads them, the
     add-on rates ticked counted in one mute line, and a line's own acts
     in its ⋯ (Edit a custom line, Tax code, Move up, Move down, Remove).
     On a phone it is not drawn, and View quote turns the sheet to the
     lines instead. */
  function sidePaint(d) {
    var box = $('qbSide');
    if (!box) return;
    var t = (d && d.totals) || {};
    var lines = d ? MON.planFold(d.lines || [], t.currency) : [];
    var board = B ? boardLines().map(function (l) { return l.key; }) : [];
    var row = function (l) {
      var ours = B && onBoard(l.brand) && (!B.sent || l.brand === boardAt());
      var mine = ours && board.indexOf(l.key) > -1, at = ours ? board.indexOf(l.key) : -1, items = [];
      if (mine) {
        if (l.kind === 'custom') items.push(['edit', 2, 'Edit']);
        if (taxOpts(l, t)) items.push(['tax', 2, 'Change tax code']);
        if (at > 0) items.push(['up', 2, 'Move up']);
        if (at > -1 && at < board.length - 1) items.push(['down', 2, 'Move down']);
        if (l.kind === 'custom' || (l.basis === 'once' && l.slug && onceBox(l.slug))) items.push(['remove', 6, 'Remove']);
      }
      return '<div class="qb-sideline" data-key="' + esc(l.key || '') + '"><span class="qb-sidename">' + esc(l.label) +
        (Number(l.qty) > 1 && l.kind !== 'package' && l.kind !== 'plan' ? ' × ' + esc(l.qty) : '') + '</span>' +
        '<span class="qb-fig">' + esc(l.in_plan ? 'In plan' : CUR + ' ' + acct(l.amount)) + '</span>' +
        '<span class="team-act qb-sideact">' + (items.length ? '<button class="kmenu-btn" type="button" aria-label="' + esc('More actions, ' + l.label) + '" aria-expanded="false">' + DOTS + '</button>' +
          '<div class="kmenu" data-menu hidden>' + items.map(function (x) {
            return '<button class="kmenu-item" data-g="' + x[1] + '" data-a="' + x[0] + '" type="button" role="menuitem">' + esc(x[2]) + '</button>';
          }).join('') + '</div>' : '') + '</span></div>';
    };
    /* The totals in the quotation's own order, each subtotal before its
       SST, so no tax row stands apart from the figure it is on. */
    var tot = d ? totRows(d) : [];
    var group = function (name, list) {
      if (!list.length) return '';
      return '<div class="qb-sidegroup"><p class="qb-sidegh">' + esc(name) + '</p>' + list.map(row).join('') + '</div>';
    };
    var month = lines.filter(function (l) { return l.basis === 'month'; }), once = lines.filter(function (l) { return l.basis !== 'month'; });
    var ads = Number(t.budget) > 0 ? '<div class="qb-sidegroup"><p class="qb-sidegh">Advertising budget</p><div class="qb-sideline"><span class="qb-sidename">Per month, not included</span>' +
      '<span class="qb-fig">' + esc('Up to ' + CUR + ' ' + whole(t.budget)) + '</span><span class="qb-sideact"></span></div></div>' : '';
    var n = B ? aoAll().filter(function (k) { return (B.aoOn || []).indexOf(k) >= 0; }).length : 0;
    /* Several brands (BUILD QUOTE ON ONE SHEET): a group a brand, its name
       across the Summary over its figure, then its lines. */
    var byBrand = '';
    if (d && B && B.sent && B.sent.length > 1) {
      byBrand = B.sent.map(function (bi, k) {
        var mine = MON.planFold((d.lines || []).filter(function (l) { return l.brand === k; }), t.currency), fig = brandFig(bi);
        if (!mine.length) return '';
        return '<div class="qb-sidegroup qb-sidebrand"><p class="qb-sidebn">' + esc(brandWord(B.brands[bi])) + '</p>' +
          (fig[1] ? '<p class="qb-sidebf">' + esc(fig[0] + ' ' + fig[1].replace(/^Monthly/, 'monthly').replace(/^One-time/, 'one-time')) + '</p>' : '') + mine.map(row).join('') + '</div>';
      }).join('');
    }
    box.innerHTML = '<p class="qb-sidehead">Summary</p>' +
      (lines.length ? (byBrand || group('Monthly', month) + group('One-time', once)) + ads +
        totDl(tot, 'qb-sidetot', 'qb-sidenote') : ads + '<p class="qb-sidenote">No items.</p>') +
      (n ? '<p class="qb-sidenote">' + n + (n === 1 ? ' add-on rate listed' : ' add-on rates listed') + '</p>' : '');
    sideFit();
  }
  /* The Summary sticks under the sheet's head and scrolls on its own
     where it is taller than the sheet's body. */
  function sideFit() {
    var body = $('qbBox') && $('qbBox').querySelector('.sheet-body');
    if (body && body.clientHeight) body.style.setProperty('--qb-side-max', Math.max(160, body.clientHeight - 32) + 'px');
  }
  function sideOn() { var b = $('qbSide'); return !!b && b.getClientRects().length > 0; }
  function onceBox(slug) {
    return Array.prototype.filter.call(document.querySelectorAll('#qbOnce input[data-slug]'), function (i) { return i.getAttribute('data-slug') === slug; })[0] || null;
  }
  function sideAct(a, key) {
    if (!B || !B.priced) return;
    var l = boardLines().filter(function (x) { return x.key === key; })[0];
    if (!l) return;
    if (a === 'up' || a === 'down') {
      var keys = boardLines().map(function (x) { return x.key; });
      var i = keys.indexOf(key), j = i + (a === 'up' ? -1 : 1);
      if (i < 0 || j < 0 || j >= keys.length) return;
      var tmp = keys[i]; keys[i] = keys[j]; keys[j] = tmp;
      B.order = keys;
      preview();
      return;
    }
    var cus = l.kind === 'custom' ? document.querySelectorAll('#qbCusRows [data-cus]')[Number(String(key).split('|')[1]) - 1] : null;
    if (a === 'edit') {
      if (!B.open) boardTo(B.bi);
      var nm = cus && cus.querySelector('.qb-cusname');
      if (nm) { nm.scrollIntoView({ block: 'center' }); nm.focus(); }
      return;
    }
    if (a === 'remove') {
      if (cus) { var x = cus.querySelector('.qb-cusx'); if (x) x.click(); return; }
      var ob = l.slug && onceBox(l.slug);
      if (ob) { ob.value = '0'; ob.dispatchEvent(new Event('input', { bubbles: true })); ob.dispatchEvent(new Event('change', { bubbles: true })); }
      return;
    }
    if (a === 'tax') {
      var tx = taxOpts(l, B.priced.totals || {});
      if (!tx) return;
      window.ADspaceConfirm.ask({ title: 'Tax code', go: 'Save',
        field: { name: 'tax', label: l.label, choices: tx.opts, value: tx.cur, required: false } }, function (v) {
        if (!B) return;
        v = typeof v === 'string' ? v : (v && v.tax) || '';
        var e0 = B.edits[key] || {};
        if (v) e0.tax = v; else delete e0.tax;
        if (Object.keys(e0).length) B.edits[key] = e0; else delete B.edits[key];
        preview();
      });
    }
  }

  function wire() {
    if (!$('qbBox') || wire.done) return;
    wire.done = true;
    var on = function () { if (!B) return; pkgRead(); pkgFigs(); sync(); preview(); };
    /* A brand's type, as three tiles (2026-11-25). */
    Array.prototype.forEach.call($('qbTypes').querySelectorAll('[data-kind]'), function (t) {
      var m = t.querySelector('.qb-typemark'), I = window.ADspaceIcons;
      if (m && I && I.svg) m.innerHTML = I.svg(m.getAttribute('data-mark'));
      t.addEventListener('click', function () { kindPick(t.getAttribute('data-kind')); brandSay(''); });
    });
    $('qbSide').addEventListener('click', function (e) {
      var btn = e.target.closest('.kmenu-btn'), it = e.target.closest('.kmenu-item');
      if (it) {
        it.closest('[data-menu]').hidden = true;
        sideAct(it.getAttribute('data-a'), it.closest('[data-key]').getAttribute('data-key'));
        return;
      }
      if (!btn) return;
      var menu = btn.parentNode.querySelector('[data-menu]'), open = menu.hidden;
      Array.prototype.forEach.call(document.querySelectorAll('.kmenu'), function (m) { m.hidden = true; });
      menu.hidden = !open;
      btn.setAttribute('aria-expanded', String(open));
      if (open) window.ADspaceMenu.place(btn, menu);
    });
    /* The Summary shows or gives way as the sheet narrows: View quote
       follows it, and the lines turned open close where the Summary
       holds them. */
    window.addEventListener('resize', function () {
      if (!B || $('qbBox').hidden) return;
      viewSay(); sideFit();
    });
    $('qbPkgAdd').addEventListener('change', function () {
      if (!B || !B.pkg || !this.value) return;
      pkgRead();
      B.pkg.items.push({ slug: this.value, qty: 1, extra: null });
      pkgPaint(); on();
      var q = document.getElementById('qbPk-' + B.pkg.items[B.pkg.items.length - 1].slug);
      if (q) q.focus();
    });
    $('qbPkgRows').addEventListener('click', function (e) {
      var x = e.target.closest('.qb-pkgx');
      if (!x || !B || !B.pkg) return;
      pkgRead();
      var sl = x.closest('[data-pk]').getAttribute('data-pk');
      B.pkg.items = B.pkg.items.filter(function (it) { return it.slug !== sl; });
      pkgPaint(); on(); $('qbPkgAdd').focus();
    });
    $('qbPkgIncl').addEventListener('click', function (e) {
      var x = e.target.closest('.qb-pkgx');
      if (!x || !B || !B.pkg) return;
      pkgRead();
      B.pkg.incl.splice(Number(x.closest('[data-in]').getAttribute('data-in')), 1);
      pkgPaint(); on(); $('qbPkgInclAdd').focus();
    });
    $('qbPkgInclAdd').addEventListener('click', function () {
      if (!B || !B.pkg) return;
      pkgRead();
      B.pkg.incl.push({ text: '', on: true });
      pkgPaint();
      var rows = $('qbPkgIncl').querySelectorAll('[data-in] input[type="text"]');
      rows[rows.length - 1].focus();
    });
    ['qbPkgName', 'qbPkgPrice', 'qbPkgIncl', 'qbPkgExtra', 'qbPkgRows'].forEach(function (id) { $(id).addEventListener('input', on); });
    ['qbPkgBasis', 'qbPkgIncl'].forEach(function (id) { $(id).addEventListener('change', on); });
    /* The brands' cards: a head opens or shuts its card, its ⋯ duplicates
       or removes the brand; Add brand opens a new card. */
    $('qbBrandAdd').addEventListener('click', function () { brandNew(); });
    $('qbBrandCards').addEventListener('click', function (e) {
      if (!B) return;
      var cardEl = e.target.closest('.qb-bcard');
      if (!cardEl || !$('qbBrandCards').contains(cardEl)) return;
      var i = Number(cardEl.getAttribute('data-bi'));
      var it = e.target.closest('.qb-bact .kmenu-item'), btn = e.target.closest('.qb-bact .kmenu-btn');
      if (it) {
        it.closest('[data-menu]').hidden = true;
        if (it.getAttribute('data-a') === 'dup') brandNew(i); else brandRemove(i);
        return;
      }
      if (btn) {
        var menu = btn.parentNode.querySelector('[data-menu]'), open = menu.hidden;
        Array.prototype.forEach.call(document.querySelectorAll('.kmenu'), function (m) { m.hidden = true; });
        menu.hidden = !open;
        btn.setAttribute('aria-expanded', String(open));
        if (open) window.ADspaceMenu.place(btn, menu);
        return;
      }
      if (e.target.closest('.qb-bopen')) boardTo(i);
    });
    $('qbBrandName').addEventListener('input', function () {
      if (!B || !B.brands[B.bi]) return;
      B.brands[B.bi].name = this.value;
      cards();
      preview();
    });
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
    ['qbMix', 'qbBudget', 'qbTerm', 'qbTranslate', 'qbGraphic', 'qbReel', 'qbDate'].forEach(function (id) {
      $(id).addEventListener('change', on);
      $(id).addEventListener('input', on);
    });
    $('qbDate').addEventListener('change', termOptions);
    /* A date on another version's days takes that version, until one is chosen. */
    $('qbDate').addEventListener('change', function () {
      if (!B || B.cardPicked || !B.card) return;
      var v = cardOn(qbDay());
      if (v && v !== B.card.version) rebuildOn(v, false);
    });
    $('qbCard').addEventListener('change', function () { if (B && B.card && this.value !== B.card.version) rebuildOn(this.value, true); });
    $('qbPay').addEventListener('change', on);
    $('qbTermDisc').addEventListener('change', on);
    $('qbPeriod').addEventListener('change', on);
    $('qbAddons').addEventListener('change', function (e) {
      var k = e.target && e.target.getAttribute('data-ao');
      if (!B || !k) return;
      B.aoOn = (B.aoOn || []).filter(function (x) { return x !== k; });
      if (e.target.checked) B.aoOn.push(k);
      on();
    });
    $('qbTerm').addEventListener('change', discShow);
    $('qbValid').addEventListener('change', on);
    $('qbHeading').addEventListener('change', on);
    $('qbAdOn').addEventListener('change', function () {
      if (!B) return;
      $('qbAdBox').hidden = !this.checked;
      adsShow();
      if (this.checked && !document.querySelector('#qbAdRows [data-ad]')) $('qbAdRows').innerHTML = adRow(adsFirst());
      adsPaint(); on();
    });
    $('qbAdAdd').addEventListener('click', function () {
      $('qbAdRows').insertAdjacentHTML('beforeend', adRow({ platform: 'tiktok', freq: 'monthly', months: Number($('qbTerm').value) || 6 }));
      adsPaint();
      var rows = $('qbAdRows').querySelectorAll('[data-ad]');
      rows[rows.length - 1].querySelector('.qb-adplat').focus();
      on();
    });
    $('qbAdRows').addEventListener('click', function (e) {
      var x = e.target.closest('.qb-adx');
      if (!x) return;
      x.closest('[data-ad]').remove();
      if (!document.querySelector('#qbAdRows [data-ad]')) { $('qbAdOn').checked = false; $('qbAdBox').hidden = true; adsShow(); $('qbAdAddFirst').focus(); }
      else $('qbAdAdd').focus();
      adsPaint(); on();
    });
    $('qbAdRows').addEventListener('input', function (e) { var r = e.target.closest('[data-ad]'); if (r) r.removeAttribute('data-auto'); adsPaint(); on(); });
    ['qbBudget', 'qbTerm'].forEach(function (id) { $(id).addEventListener('change', adsFollow); });
    $('qbOnceAdd').addEventListener('click', function () {
      if (!B) return;
      onceShow(true);
      var f = $('qbOnce').querySelector('input');
      if (f) f.focus();
    });
    $('qbAdAddFirst').addEventListener('click', function () {
      if (!B) return;
      $('qbAdOn').checked = true;
      $('qbAdOn').dispatchEvent(new Event('change'));
      var f = $('qbAdRows').querySelector('.qb-adbud');
      if (f) f.focus();
    });
    $('qbView').addEventListener('click', function () { if (B) linesView(!$('qbBox').querySelector('.sheet-card').classList.contains('is-lines')); });
    $('qbCusAdd').addEventListener('click', function () {
      $('qbCusRows').insertAdjacentHTML('beforeend', cusRow({ basis: 'month', months: Number($('qbTerm').value) || 6 }));
      var rows = $('qbCusRows').querySelectorAll('[data-cus]');
      rows[rows.length - 1].querySelector('.qb-cusname').focus();
      on();
    });
    $('qbRenew').addEventListener('click', function () { if (B) renewOpen(); });
    $('qbRenewBox').addEventListener('click', function (e) {
      var a = e.target.closest('[data-a]');
      if (!a) return;
      if (a.getAttribute('data-a') === 'renew') { renewTake(); on(); }
      else { $('qbRenewBox').hidden = true; $('qbRenewBox').innerHTML = ''; $('qbRenew').focus(); }
    });
    $('qbCusRows').addEventListener('click', function (e) {
      var x = e.target.closest('.qb-cusx');
      if (!x) return;
      x.closest('[data-cus]').remove();
      $('qbCusAdd').focus();
      on();
    });
    $('qbCusRows').addEventListener('input', function () { on(); });
    $('qbCusRows').addEventListener('change', function (e) {
      if (e.target.type !== 'date') return;
      on();
    });
    $('qbBillTo').addEventListener('change', function () { if (B) B.entity = this.value; on(); });
    $('qbTerms').addEventListener('input', function () { on(); });
    /* A select changes once; a typed figure has already repriced on
       input, so leaving it (a press on Create) does not reprice again. */
    $('qbAdRows').addEventListener('change', function (e) { if (e.target.tagName === 'SELECT') { adsPaint(); on(); } });
    ['qbPlats', 'qbLangs', 'qbOnce'].forEach(function (id) { $(id).addEventListener('change', on); $(id).addEventListener('input', on); });
    /* A figure typed: Create waits for the figures it will keep; Enter or
       leaving the field prices it again. Empty, or the card's own figure,
       puts back the card's. */
    /* The tax select reads its code closed and the rate in its list. */
    ['mousedown', 'focusin'].forEach(function (ev) {
      $('qbLines').addEventListener(ev, function (e) { var t = e.target.closest && e.target.closest('.qb-tax'); if (t) taxWord(t, true); });
    });
    $('qbLines').addEventListener('focusout', function (e) { var t = e.target.closest && e.target.closest('.qb-tax'); if (t) taxWord(t, false); });
    $('qbLines').addEventListener('input', function (e) {
      if (B && e.target.closest('.qb-val')) { $('qbSave').disabled = true; $('qbPreview').disabled = true; }
    });
    /* A line's description, edited for this quotation (2026-11-13). */
    /* A line renamed, or moved, for this quotation (2026-11-16). */
    $('qbLines').addEventListener('click', function (e) {
      if (!B) return;
      var mv = e.target.closest('.qb-move');
      if (mv) {
        var mb = brandOf(mv), keys = linesAt(mb).map(function (l) { return l.key; });
        var i = keys.indexOf(mv.getAttribute('data-key')), j = i + Number(mv.getAttribute('data-move'));
        if (i < 0 || j < 0 || j >= keys.length) return;
        var tmp = keys[i]; keys[i] = keys[j]; keys[j] = tmp;
        setOrder(mb, keys);
        preview();
        return;
      }
      var nk = e.target.closest('.qb-name-edit');
      if (nk) {
        B.nameKey = lineId(brandOf(nk), nk.closest('.qb-incl').getAttribute('data-key')); B.descKey = null;
        $('qbLines').innerHTML = table(B.priced);
        var ni = $('qbLines').querySelector('.qb-name-in');
        if (ni) { ni.focus(); ni.select(); }
        return;
      }
      if (e.target.closest('.qb-name-cancel')) { B.nameKey = null; $('qbLines').innerHTML = table(B.priced); return; }
      var nd = e.target.closest('.qb-name-done');
      if (nd) nameDone(nd.getAttribute('data-key'), brandOf(nd));
    });
    function nameDone(k, bk) {
      var inp = $('qbLines').querySelector('.qb-name-in');
      if (!inp) return;
      var v = inp.value.replace(/\s+/g, ' ').trim();
      var line = linesAt(bk).filter(function (l) { return l.key === k; })[0] || {};
      var card = line.list_label != null ? line.list_label : line.label;
      var e4 = editsAt(bk)[k] || {};
      /* Empty, or the Rate Card's own name, puts back the card's. */
      if (!v || v === card) delete e4.name; else e4.name = v;
      putEdit(bk, k, e4);
      B.nameKey = null;
      preview();
    }
    $('qbLines').addEventListener('keydown', function (e) {
      var ni = e.target.closest('.qb-name-in');
      if (!ni || e.isComposing) return;
      if (e.key === 'Enter') { e.preventDefault(); nameDone(ni.getAttribute('data-key'), brandOf(ni)); }
      else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); B.nameKey = null; $('qbLines').innerHTML = table(B.priced); }
    });
    $('qbLines').addEventListener('click', function (e) {
      var w = e.target.closest('.qb-incl[data-key]');
      if (!w || !B) return;
      var k = w.getAttribute('data-key'), wb = brandOf(w);
      if (e.target.closest('.qb-desc-edit')) {
        B.descKey = lineId(wb, k); $('qbLines').innerHTML = table(B.priced);
        var ta = $('qbLines').querySelector('.qb-desc');
        if (ta) { ta.focus(); ta.setSelectionRange(ta.value.length, ta.value.length); }
      } else if (e.target.closest('.qb-desc-cancel')) {
        B.descKey = null; $('qbLines').innerHTML = table(B.priced);
      } else if (e.target.closest('.qb-desc-done')) {
        var pts = String(w.querySelector('.qb-desc').value).split(/\r?\n/)
          .map(function (x) { return x.replace(/^\s*[-•·]\s*/, '').trim(); }).filter(Boolean);
        if (pts.length > 12 || pts.some(function (x) { return x.length > 300; })) {
          $('qbMsg').textContent = 'Enter up to 12 points, each up to 300 characters.'; $('qbMsg').className = 'msg err';
          return;
        }
        var e3 = editsAt(wb)[k] || {};
        if (pts.length) e3.detail = pts; else delete e3.detail;
        putEdit(wb, k, e3);
        B.descKey = null; $('qbMsg').textContent = ''; $('qbMsg').className = 'msg';
        preview();
      } else if (e.target.closest('.qb-desc-card')) {
        var e5 = editsAt(wb)[k];
        if (e5) { delete e5.detail; delete e5.name; putEdit(wb, k, e5); }
        preview();
      }
    });
    $('qbLines').addEventListener('keydown', function (e) {
      if (e.key === 'Enter' && !e.isComposing && e.target.closest('.qb-val')) { e.preventDefault(); e.target.blur(); }
    });
    $('qbLines').addEventListener('change', function (e) {
      var ip = e.target.closest('.qb-inplan input');
      if (ip && B) {
        var b2 = brandOf(ip), k2 = ip.getAttribute('data-key'), e2 = editsAt(b2)[k2] || {};
        if (ip.checked) delete e2.incl; else e2.incl = false;
        putEdit(b2, k2, e2);
        preview();
        return;
      }
      var tx = e.target.closest('.qb-tax');
      if (tx && B) {
        var b0 = brandOf(tx), k0 = tx.getAttribute('data-key'), e0 = editsAt(b0)[k0] || {};
        if (tx.value) e0.tax = tx.value; else delete e0.tax;
        putEdit(b0, k0, e0);
        preview();
        return;
      }
      var i = e.target.closest('.qb-val');
      if (!i || !B) return;
      var bk = brandOf(i), k = i.getAttribute('data-key'), what = i.getAttribute('data-what');
      var raw = String(i.value).replace(/[,\s]/g, '').replace(/^(RM|S\$)/i, '');
      var ok = what === 'rate' ? /^[0-9]{1,7}(\.[0-9]{1,2})?$/.test(raw) :
        what === 'qty' ? /^[0-9]{1,4}$/.test(raw) && Number(raw) >= 1 : /^[0-9]{1,2}$/.test(raw) && Number(raw) >= 1 && Number(raw) <= 36;
      /* A quantity a stepper above holds (an additional content piece, a
         one-time item, an add-on) is that stepper's: typed here it moves the
         stepper, never an override beside it, so the two never disagree
         (the user, 2026-11-07: Qty 3 below, the stepper 2 above). */
      var step = what === 'qty' && ok && stepAt(bk, k);
      if (step && Number(raw) > step.max) {
        i.value = step.now;
        $('qbMsg').textContent = 'Enter a quantity up to ' + step.max + '.'; $('qbMsg').className = 'msg err';
        i.focus();
        return;
      }
      if (step) {
        step.set(Number(raw));
        var eq = editsAt(bk)[k];
        if (eq) { delete eq.qty; putEdit(bk, k, eq); }
        $('qbMsg').textContent = ''; $('qbMsg').className = 'msg';
        preview();
        return;
      }
      var e1 = editsAt(bk)[k] || {};
      /* A one-time Rate Card item: a number of months bills it monthly,
         empty or 0 keeps it one-time (2026-11-12). */
      if (what === 'months' && i.classList.contains('qb-flex')) {
        if (raw === '' || /^0+$/.test(raw)) { delete e1.basis; delete e1.months; }
        else if (ok) { e1.basis = 'month'; e1.months = raw; }
        else { $('qbMsg').textContent = SAID['bad-edit']; $('qbMsg').className = 'msg err'; i.focus(); return; }
        putEdit(bk, k, e1);
        $('qbMsg').textContent = ''; $('qbMsg').className = 'msg';
        preview();
        return;
      }
      if (raw === '') delete e1[what];
      else if (ok) e1[what] = raw;
      else {
        $('qbMsg').textContent = SAID['bad-edit']; $('qbMsg').className = 'msg err';
        i.focus(); return;
      }
      putEdit(bk, k, e1);
      $('qbMsg').textContent = ''; $('qbMsg').className = 'msg';
      preview();
    });
    $('qbCancel').addEventListener('click', function () { window.ADspaceSheet.close(); B = null; });
    $('qbClose').addEventListener('click', function () { $('qbCancel').click(); });
    $('qbDraft').addEventListener('click', draftPress);
    /* Preview PDF (2026-10-31; the user: "preview pdf … before sending"):
       the quotation as it is priced now, drawn under DRAFT with the
       reference PREVIEW; nothing is made and no number is spent. */
    /* Preview PDF: in the foot at a desk, under the lines on a phone. */
    var previewPdf = function () {
      if (!B || !B.priced || !window.ADspaceQuotePdf) return;
      var d = B.priced, ctx = B.ctx, btn = this;
      var today = qbDay();
      var days = Number($('qbValid').value) || validDefault(today);
      var me = window.ADspaceAdmin && window.ADspaceAdmin.me ? window.ADspaceAdmin.me() : null;
      var q = { ref: 'PREVIEW', brand: ctx.client.name, issued_at: today, valid_until: window.ADspaceClock.addDays(today, days),
        made_by: (B.editing && B.editing.made_by) || (me && me.name) || '',
        source: B.editing ? B.editing.source : undefined, contact: B.editing ? B.editing.contact : undefined,
        version: d.version, lines: d.lines, totals: Object.assign({}, d.totals, extras(B.sel)), selection: B.sel };
      var tab = window.ADspaceDocs.previewTab();
      btn.disabled = true;
      drawPdf(q, ctx, { draft: true }).then(function (blob) {
        btn.disabled = false;
        window.ADspaceDocs.save(blob, 'Preview ' + window.ADspaceQuotePdf.fileName(q), tab);
      }).catch(function (e) {
        btn.disabled = false;
        if (tab) try { tab.close(); } catch (x) {}
        $('qbMsg').textContent = said(e) || 'The preview could not be generated.'; $('qbMsg').className = 'msg err';
      });
    };
    $('qbPreview').addEventListener('click', previewPdf);
    $('qbPreviewFoot').addEventListener('click', previewPdf);
    $('qbSave').addEventListener('click', function () {
      if (!B) return;
      var go = this;
      /* Create checks every card and opens the first with a fault
         (BUILD QUOTE ON ONE SHEET); a card left empty beside priced ones
         is a fault too, so nothing chosen is dropped unseen. */
      keepBrand(selection());
      var bad = -1, wrong = '';
      if (B.open) wrong = adsWrong() || cusWrong();
      if (wrong) bad = B.bi;
      else B.brands.some(function (b, i) { var w = brandWrong(b); if (w) { bad = i; wrong = w; } return Boolean(w); });
      if (!wrong && $('qbTerms').value.split(/\r?\n/).filter(function (x) { return x.trim(); }).length > 10) wrong = window.ADspaceWords.line.terms;
      if (wrong) {
        if (bad > -1 && (bad !== B.bi || !B.open)) openCard(bad);
        brandSay(wrong);
        if (bad > -1) brandFocus(wrong); else $('qbTerms').focus();
        return;
      }
      if (!B.priced) { if (B.err) brandSay(B.err); return; }
      B.idem = B.idem || (window.ADspaceDocs && window.ADspaceDocs.idemKey ? window.ADspaceDocs.idemKey() : (window.crypto && window.crypto.randomUUID ? window.crypto.randomUUID() : String(Date.now()) + Math.random().toString(36).slice(2)));
      go.disabled = true; B.saving = true;
      if (B.editing) {
        var ed = B.editing;
        B.ctx.db.rpc('quotation_edit', { p_id: ed.id, p_sel: B.sel }).then(function (r) {
          var d = r.data || {};
          go.disabled = false; if (B) B.saving = false;
          /* Lines or a letter came from it (removed lines and voided
             letters count too, as the database holds them): the same sheet
             becomes its revision, kept as typed, Save making the next
             quotation (audit 2026-11-08, 3). */
          if (!r.error && (d.error === 'lines' || d.error === 'letter')) {
            B.revises = ed; B.editing = null;
            $('qbSave').textContent = 'Create quotation';
            $('qbMsg').textContent = (d.error === 'lines' ? 'Service lines were created from ' : 'A Letter of Offer was issued from ') + ed.ref +
              ', so it cannot be edited. Create quotation will create a revised quotation.';
            $('qbMsg').className = 'msg warn';
            return;
          }
          if (r.error || d.error) { $('qbMsg').textContent = said(r.error || d.error); $('qbMsg').className = 'msg err'; return; }
          var ctx = B.ctx;
          window.ADspaceSheet.close();
          B = null;
          ctx.reload(function () { ctx.msg('qtMsg', refOf(ed) + ' saved.', 'ok'); markNew(refOf(ed)); });
        }).catch(function (e) { go.disabled = false; if (B) B.saving = false; $('qbMsg').textContent = said(e); $('qbMsg').className = 'msg err'; });
        return;
      }
      /* Two brands or more (the user, 2026-11-24: "give option to split"):
         Create asks whether they make one quotation or a quotation each,
         one quotation the answer it opens on. A revision stays one. */
      if (B.sel.brands && B.sel.brands.length > 1 && !B.revises && window.ADspaceConfirm) {
        go.disabled = false; if (B) B.saving = false;
        window.ADspaceConfirm.ask({ title: 'Create quotation', go: 'Create',
          field: { name: 'split', label: 'Quotations', seg: true, value: 'one', required: true,
            choices: [['one', 'One for all brands'], ['each', 'One per brand']] } }, function (v) {
          if (!B) return;
          if ((v && v.split) === 'each') makeEach(go); else makeOne(go);
        });
        return;
      }
      makeOne(go);
    });
    /* A quotation for each brand, made together from the same list, each
       its own reference, PDF, link, signature and invoicing; a key each, so
       a second press makes none twice. */
    function makeEach(go) {
      var sel = B.sel, ctx = B.ctx, idem = B.idem, made = [], at = 0;
      go.disabled = true; B.saving = true;
      var next = function () {
        if (at >= sel.brands.length) {
          if (B) B.made = true;
          window.ADspaceSheet.close();
          B = null;
          ctx.reload(function () { ctx.msg('qtMsg', made.length + ' drafts saved.', 'ok'); made.map(dref).forEach(markNew); });
          return;
        }
        var one = Object.assign({}, sel, { brands: [sel.brands[at]] });
        var mine = (sel.ads || []).filter(function (r) { return r.brand === at; }).map(function (r) { return Object.assign({}, r, { brand: 0 }); });
        if (mine.length) one.ads = mine; else delete one.ads;
        ctx.db.rpc('quotation_create', { p_client: ctx.client.id, p_sel: one, p_idem: idem + '-' + (at + 1) }).then(function (r) {
          var d = r.data || {};
          if (r.error || d.error) {
            go.disabled = false; if (B) B.saving = false;
            if (!B) return;
            $('qbMsg').textContent = (made.length ? made.length + (made.length === 1 ? ' draft' : ' drafts') + ' saved. ' : '') + 'The quotation for ' + brandWord(sel.brands[at]) + ' was not made. ' + said(r.error || d.error);
            $('qbMsg').className = 'msg err';
            return;
          }
          made.push(d.ref); at++; next();
        }).catch(function (e) { go.disabled = false; if (B) B.saving = false; if (B) { $('qbMsg').textContent = said(e); $('qbMsg').className = 'msg err'; } });
      };
      next();
    }
    function makeOne(go) {
      go.disabled = true; B.saving = true;
      B.ctx.db.rpc('quotation_create', { p_client: B.ctx.client.id, p_sel: B.sel, p_idem: B.idem }).then(function (r) {
        var d = r.data || {};
        go.disabled = false; if (B) B.saving = false;
        if (r.error || d.error) { $('qbMsg').textContent = said(r.error || d.error); $('qbMsg').className = 'msg err'; return; }
        var ctx = B.ctx, revises = B.revises, opener = B.opener;
        B.made = true;
        window.ADspaceSheet.close();
        B = null;
        if (!revises) { ctx.reload(function () { ctx.msg('qtMsg', 'Draft saved.', 'ok'); markNew(dref(d.ref)); }); return; }
        ctx.db.rpc('quotation_replace', { p_new: d.id, p_old: revises.id }).then(function (r2) {
          var e2 = (r2 && r2.error) || (r2 && r2.data && r2.data.error);
          ctx.reload(function (rows) {
            if (e2) { ctx.msg('qtMsg', 'Draft saved. It is not recorded as a revision of ' + revises.ref + ' (' + said(e2) + '). Remove it and edit ' + revises.ref + ' again.', 'err'); return; }
            /* The revision is a draft: confirmed, it takes the next -Rn under
               its family and revises the earlier then (2026-11-26). */
            ctx.msg('qtMsg', 'Draft revision saved.', 'ok'); markNew(dref(d.ref));
          });
        }).catch(function (e) { ctx.reload(function () { ctx.msg('qtMsg', said(e), 'err'); }); });
      }).catch(function (e) { go.disabled = false; if (B) B.saving = false; $('qbMsg').textContent = said(e); $('qbMsg').className = 'msg err'; });
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', wire); else wire();

  /* The open card's board shown, a type chosen where asked (the suites
     reach a type's own controls this way). */
  function show(kind) { if (!B) return; if (!B.open) boardTo(B.bi); if (kind && kind !== B.kind) kindPick(kind); }
  window.ADspaceQuotes = { show: show, load: load, paint: paint, overview: overview, build: build, stateOf: stateOf, headline: headline, offerable: offerable, sealedCopy: sealedCopy };
})();
