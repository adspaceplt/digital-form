/* Bukku (2026-10-18; the user: "build API that push the client or supplier
 * details over to Bukku"): a client's billing, or a supplier's details,
 * sent by hand as one Bukku contact through `bukku-sync`. A contact already
 * in Bukku is linked, never made twice: the sheet offers the contacts with
 * the same registration number or name first, else a new one under Bukku's
 * own next code. What changes is shown field by field before it goes. The
 * Client ID and the Supplier ID ride in the Bukku custom fields chosen on
 * the Settings page (Accounting, Bukku). A supplier linked to a client is the
 * same contact, typed Customer and Supplier.
 *
 *   ADspaceBukku.group(host, kind, id, opts)  — the record's Bukku band, Unlink in its ⋯
 *                                               (kind client, supplier, entity or creator; opts.after on a link's change;
 *                                               opts.read(r) after a client's or entity's read from Bukku;
 *                                               opts.lead: linked, the band leads its container)
 *   ADspaceBukku.held(kind, id)               — the last read where Bukku holds the record's billing, else null
 *   ADspaceBukku.state(kind, id)              — reading, held, differs, down or none
 *   ADspaceBukku.save(kind, id, values)       — the Billing sheet's changes saved straight to Bukku
 *   ADspaceBukku.fresh(kind, id)              — read again at the next band (a record opened afresh)
 *   ADspaceBukku.send(kind, id, btn, done)    — the Link to Bukku sheet (a supplier's Send to Bukku)
 *   ADspaceBukku.openConfig(btn, say)         — Settings' Bukku sheet
 *   ADspaceBukku.configLine()                 — Settings' Bukku value line
 */
(function () {
  /* Bukku's own logo on every Bukku band (the user, 2026-11-11), a light
     copy for the dark theme; the word stays for a screen reader. Never on a
     page or an email a client reads. */
  var MARK = '<b class="bk-t"><img class="bk-logo" src="/img/bukku-logo.png?v=20261111c" alt="" width="45" height="16"><span class="sr">Bukku</span></b>';
  var API = window.ADspaceAPI;
  var X = window.ADspaceIcons.glyph('x');

  function db() { return API && API.client; }
  function $(id) { return document.getElementById(id); }
  function esc(s) { return window.ADspaceWords.esc(s); }
  function day(iso) { return iso && window.ADspaceClock ? window.ADspaceClock.date(iso) : ''; }
  function may(k, l) { var A = window.ADspaceAdmin; return Boolean(A && A.may && A.may(k, l)); }
  function mayWork(kind) { return kind === 'supplier' ? may('suppliers', 'work') : kind === 'creator' ? may('campaigns.pay', 'work') : kind === 'member' ? may('team.personnel', 'manage') : may('clients.billing', 'work'); }
  /* A client's or billing entity's billing is Bukku's once linked; a creator is sent. */
  function holds(kind) { return kind === 'client' || kind === 'entity'; }
  /* Linked first, then read from Bukku as the record opens: a client, an
     entity and a supplier (2026-11-22, the user: "Link clients, Link
     creators, But no link suppliers?"). A supplier's details stay the
     portal's: what differs waits on Send to Bukku or Use Bukku's. */
  function reads(kind) { return holds(kind) || kind === 'supplier'; }

  var SAID = {
    denied: 'You do not have permission to send this record to Bukku. Please ask an admin.',
    'not-found': 'This record no longer exists.',
    'not-active': 'Approve the supplier before it is sent to Bukku.',
    'no-details': 'Approve the creator\'s payment details before they are sent to Bukku.',
    'bukku-not-set-up': window.ADspaceWords.line.bukkuNotSetUp,
    'bukku-token': 'Bukku is not available at the moment. Please contact an admin.',
    'bukku-unreachable': window.ADspaceWords.line.bukkuNoAnswer,
    'bukku-gone': 'That contact is no longer in Bukku. Choose another.',
    'no-field': 'Choose Bukku\'s Client ID and Supplier ID fields on the Settings page (Accounting, Bukku) first.',
    linked: 'This record is already linked to a contact in Bukku. Refresh the page.',
    taken: 'That Bukku contact is linked to another record in the portal. Choose another.',
    'not-offered': 'That Bukku contact does not match this record. Choose one of the contacts offered.',
    busy: 'Sending to Bukku is already in progress. Please refresh the page in a moment.',
    /* A new contact sent and not answered may stand in Bukku: the next Send
       links it rather than making another (the Bukku review, 2026-11-25). */
    'not-confirmed': 'Bukku did not confirm the contact. Please refresh the page in a moment, then send it again.',
    'not-filed': 'The contact was sent to Bukku, but the portal did not save the link. Send again to link it.',
    moved: 'Not restored, as it has since been linked again.',
    'needs-update': 'This feature is not available yet. Please contact an admin.',
    'bad-value': 'Choose a field from the list.',
    'bad-sku': 'Enter the item SKU as it appears in Bukku, for example P995.',
    'bad-class': 'Enter the classification code as three digits, for example 037.',
    'bad-account': 'Choose the account.',
    'bad-number': 'Enter the invoice number as it appears in Bukku, for example AINV000123.',
    'not-held': 'Bukku and the portal have different details. Choose Send to Bukku or Use Bukku\'s first.',
    stale: 'Not saved. This record was changed in Bukku. The latest version is now shown.',
    'bad-email': 'Enter a valid email address.',
    'no-name': 'Enter the Registered Company Name.',
    'no-address': 'Enter the billing address.',
    'bad-contact': 'Choose one of the client\'s contacts.',
    'not-linked': 'This record is no longer linked to Bukku. Refresh the page.',
    failed: 'The request failed. Please try again.'
  };
  function said(d) {
    if (!d) return SAID.failed;
    if (d.error === 'incomplete') return 'Fill in ' + (d.missing || []).join(' and ') + ' before it is sent to Bukku.';
    if (d.error === 'bukku-refused') return 'Bukku refused the request' + (d.message ? ': ' + String(d.message).replace(/\.+$/, '') : '') + '. Check the details in Bukku, then try again.';
    return SAID[d.error] || d.error || SAID.failed;
  }
  /* One call of the function; a refusal comes back as { error }. */
  function call(body) {
    return db().functions.invoke('bukku-sync', { body: body }).then(function (r) {
      return API.fnRefusal(r).then(function (code) {
        if (code) return { error: code, message: r.data && r.data.message, missing: r.data && r.data.missing };
        return r.data || { error: 'failed' };
      });
    }, function () { return { error: 'failed' }; });
  }
  function rpc(fn, args) {
    return db().rpc(fn, args).then(function (r) {
      if (r.error) return { error: /could not find|does not exist|schema cache/i.test(r.error.message || '') ? 'needs-update' : 'failed' };
      return r.data || {};
    }, function () { return { error: 'failed' }; });
  }

  /* What was last read from Bukku, a record at a time, for this visit. */
  var READ = {};
  var WORD = { legal_name: 'Registered Company Name', company_no: 'Business Registration No.', company_no_old: 'Old Registration No.',
    tin: 'TIN', sst_no: 'SST Registration No.', person: 'Billing contact', finance_email: 'Finance email', billing_address: 'Billing address' };
  /* A supplier's fields under the supplier's own labels. */
  var SUP_WORD = Object.assign({}, WORD, { legal_name: 'Name', company_no: 'BRN', person: 'Person in charge' });
  function wordOf(kind, f) { return (kind === 'supplier' ? SUP_WORD : WORD)[f] || f; }
  function held(kind, id) { var r = READ[kind + ':' + id]; return r && r.held && !r.error && r.hash ? r : null; }
  function state(kind, id) {
    var r = READ[kind + ':' + id];
    return !r ? 'none' : r.reading ? 'reading' : r.error ? 'down' : r.held ? 'held' : 'differs';
  }
  function fresh(kind, id) { delete READ[kind + ':' + id]; }
  /* The Billing sheet's changes saved straight to Bukku, then read back:
     `values` holds only what changed. A refusal is said in the sheet. */
  function save(kind, id, values) {
    var r = held(kind, id);
    if (!r) return Promise.resolve({ error: 'not-held', said: said({ error: 'not-held' }) });
    return call({ action: 'save', kind: kind, id: id, values: values, expected: r.hash }).then(function (x) {
      if (x.error === 'stale' && x.values) READ[kind + ':' + id] = Object.assign({}, r, { values: x.values, hash: x.hash, changed: x.changed, at: Date.now() });
      if (x.error) return { error: x.error, said: said(x) };
      READ[kind + ':' + id] = Object.assign({}, r, { values: x.values, hash: x.hash, person_in: x.person_in, changed: [], at: Date.now() });
      return x;
    });
  }

  /* ---- The record's band -------------------------------------------------
     One shaded band at the foot of the details it sends (2026-10-29; the
     user: the group "looks incomplete … simply added"): Bukku, the contact's
     code and its state (Up to date, Details changed, Not linked), Last sent
     under it, and at the right edge Send to Bukku and a ⋯ holding Unlink.
     Unlink lets go of the link alone, nothing changed in Bukku, with Undo
     where it happened, so a record linked to the wrong contact is never a
     dead end. */
  var DOTS = window.ADspaceIcons.glyph('more');
  /* A Bukku contact's code, pressed to copy it. */
  function codeOf(c) {
    return '<button class="serial-copy bk-code" type="button" data-bk="copy" data-code="' + esc(c) + '" aria-label="Copy ' + esc(c) + '">' + esc(c) + '</button>';
  }
  function group(host, kind, id, opts) {
    if (!host) return;
    opts = opts || {};
    var work = mayWork(kind) && opts.can !== false;
    host.classList.add('bk-band');
    /* The contact's code is a copy control (the user, 2026-10-30), one
       listener a band whatever state it draws. */
    if (!host.bkCopy) {
      host.bkCopy = true;
      host.addEventListener('click', function (e) {
        var c = e.target.closest && e.target.closest('[data-bk="copy"]');
        if (c && window.ADspaceCopy) window.ADspaceCopy.to(c, c.getAttribute('data-code'));
      });
    }
    host.innerHTML = '<div class="bk-l">' + MARK + '<span class="muted">Loading.</span></div>';
    /* What the record lacks is read up front: a record that cannot be sent
       draws no Send, and says what is missing in one line (2026-10-20,
       BKU-1). */
    Promise.all([rpc('bukku_link_get', { p_kind: kind, p_id: id }),
      work ? rpc('bukku_prepare', { p_kind: kind, p_id: id }) : Promise.resolve({})]).then(function (both) {
      var d = both[0], pre = both[1] || {};
      if (d.error === 'denied') { host.hidden = true; return; }
      host.hidden = false;
      if (d.error) { host.innerHTML = '<div class="bk-l">' + MARK + '</div><p class="msg err bk-sub">' + esc(said(d)) + '</p>'; return; }
      /* Billing from Bukku (2026-10-30): a linked client's or entity's
         billing is Bukku's, read in once a visit (Refresh reads again). */
      if (d.contact_id && reads(kind)) { readBand(d, work); return; }
      /* A creator with no approved payment details is linked, nothing
         sent (2026-11-12): their bills are then read from Bukku. */
      var linkOnly = kind === 'creator' && pre.error === 'no-details';
      var gap = work && pre.error && !linkOnly && ['denied', 'failed', 'needs-update'].indexOf(pre.error) < 0 ? said(pre) : '';
      var linked = Boolean(d.contact_id);
      /* A brand and its main entity are one company, one Bukku contact
         (2026-10-29): one holding no link of its own reads the other's,
         said as Linked through, its Unlink the other's alone. */
      var via = linked && d.via ? d.via : '';
      var state = !linked ? '<span class="chip-state is-off">Not linked</span>'
        : via ? '<span class="chip-state is-ok">Linked</span>'
        : d.changed ? '<span class="chip-state is-warn">Details changed</span>' : '<span class="chip-state is-ok">Up to date</span>';
      /* Words alone, as Send email and Create link are: no act of the
         table carries an arrow (2026-10-20, SUP-8). */
      /* A client or billing entity not yet linked is linked to the contact
         Bukku holds (2026-10-30, the user: "use link bukku instead of send
         to bukku"); Bukku then holds its billing. A supplier still sends. */
      var linkFirst = !linked && (reads(kind) || linkOnly);
      var acts = (work && !gap && !(linked && linkOnly) ? '<button class="btn btn-sm" type="button" data-bk="send" data-gate="bukku">' + (linkFirst ? 'Link to Bukku' : 'Send to Bukku') + '</button>' : '') +
        (work && linked && !via ? '<span class="team-act"><button class="kmenu-btn" type="button" data-bk="menu" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
          '<div class="kmenu" hidden><button class="kmenu-item" type="button" role="menuitem" data-g="5" data-bk="unlink">Unlink</button></div></span>' : '');
      host.innerHTML = '<div class="bk-l">' + MARK + '' + (linked ? codeOf(d.code || String(d.contact_id)) : '') + state + '</div>' +
        (via ? '<p class="bk-sub">Linked through ' + esc(via) + '</p>'
          : linked ? '<p class="bk-sub">Last sent ' + esc(day(d.sent_at)) + (d.sent_by ? ' by ' + esc(d.sent_by) : '') + '</p>' : '') +
        (acts ? '<div class="bk-acts">' + acts + '</div>' : '') +
        (gap ? '<p class="msg warn bk-gap">' + esc(gap) + '</p>' : '') +
        (opts.note ? '<p class="muted bk-note">' + esc(opts.note) + '</p>' : '') +
        (opts.said ? '<p class="msg ok bk-said" role="status">' + esc(opts.said) + '</p>' : '');
      opts.said = '';
      wire(d, linkOnly);
    });
    function readBand(d, work) {
      var key = kind + ':' + id, r = READ[key];
      /* Linked, the band leads the details it holds (`opts.lead`). */
      if (opts.lead && host.parentNode && host.parentNode.firstElementChild !== host) host.parentNode.insertBefore(host, host.parentNode.firstElementChild);
      if (r && r.at && !opts.reread) { paintRead(d, r, work); return; }
      /* One read at a time a record: a band drawn again while it runs (the
         pane repaints as its contacts and entities arrive) waits on it. */
      if (!(r && r.reading) || opts.reread) {
        var pr = call({ action: 'read', kind: kind, id: id }).then(function (x) {
          x.at = Date.now();
          if (READ[key] && READ[key].promise === pr) READ[key] = x;
          return x;
        });
        r = READ[key] = { reading: true, promise: pr };
      }
      opts.reread = false;
      host.innerHTML = '<div class="bk-l">' + MARK + '' + codeOf(d.code || String(d.contact_id)) +
        '<span class="muted">Reading Bukku.</span></div>';
      r.promise.then(function (x) {
        if (!host.isConnected) return;
        paintRead(d, READ[key] && READ[key].at ? READ[key] : x, work);
        if (opts.read && !x.told) { x.told = true; opts.read(x); }
      });
    }
    /* Held: the details are Bukku's; what moved since the last read said
       once. Not yet held: what differs, field by field, with Send to Bukku
       and Use Bukku's. Not read: the copy the portal keeps, and when. */
    function paintRead(d, r, work) {
      var code = codeOf(r.code || d.code || String(d.contact_id));
      var via = d.via ? '<p class="bk-sub">Linked through ' + esc(d.via) + '</p>' : '';
      var menu = work && !d.via ? '<span class="team-act"><button class="kmenu-btn" type="button" data-bk="menu" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
        '<div class="kmenu" hidden><button class="kmenu-item" type="button" role="menuitem" data-g="5" data-bk="unlink">Unlink</button></div></span>' : '';
      var head = '<div class="bk-l">' + MARK + '' + code;
      var when = function (iso) { return iso ? day(iso) + ', ' + (window.ADspaceClock ? window.ADspaceClock.clock(iso) : '') : ''; };
      if (r.error) {
        var copy = d.read_at ? ' The details shown were read on ' + when(d.read_at) + '.' : '';
        host.innerHTML = head + '<span class="chip-state is-warn">Not read</span></div>' +
          '<p class="bk-sub">' + esc(said(r)) + esc(copy) + '</p>' +
          '<div class="bk-acts"><button class="btn btn-sm" type="button" data-bk="refresh" data-gate="bukku">Try again</button>' + menu + '</div>';
      } else if (r.held) {
        /* What moved in Bukku is said for a minute and a half after the read, through the repaint it brings. */
        var moved = (r.changed || []).length && Date.now() - r.at < 90000 ? (r.changed || []).map(function (f) { return wordOf(kind, f); }) : [];
        var readAt = 'Read ' + esc(when(new Date(r.at).toISOString()));
        host.innerHTML = head + '<span class="chip-state is-ok">Linked</span></div>' +
          (via || '<p class="bk-sub">' + (holds(kind) ? 'Billing details from Bukku · ' + readAt : readAt) + '</p>') +
          '<div class="bk-acts"><button class="btn btn-sm" type="button" data-bk="refresh" data-gate="bukku">Refresh</button>' + menu + '</div>' +
          (moved.length ? '<p class="msg bk-said" role="status">Changed in Bukku since the details were last loaded: ' + esc(moved.join(', ')) + '.</p>' : '') +
          (r.values && r.values.person && r.person_in === false
            ? '<div class="bk-person"><p class="msg warn">Bukku\'s billing contact, ' + esc(r.values.person) + ', is not in Contacts.</p>' +
              (opts.addContact && may('clients.contacts', 'work') ? '<button class="btn btn-sm" type="button" data-bk="addct">Add as contact</button>' : '') + '</div>' : '') +
          (opts.said ? '<p class="msg ok bk-said" role="status">' + esc(opts.said) + '</p>' : '');
      } else {
        var rows = (r.differs || []);
        host.innerHTML = head + '<span class="chip-state is-warn">Differs from Bukku</span></div>' +
          (work ? '<div class="bk-acts"><button class="btn btn-sm" type="button" data-bk="send" data-gate="bukku">Send to Bukku</button>' +
            '<button class="btn btn-sm" type="button" data-bk="hold" data-gate="bukku">Use Bukku\'s</button>' + menu + '</div>' : '') +
          '<div class="bk-table bk-diff" role="table"><div class="bk-tr bk-th" role="row"><span role="columnheader">Field</span>' +
            '<span role="columnheader">Portal</span><span role="columnheader">Bukku</span></div>' +
          rows.map(function (x) {
            return '<div class="bk-tr" role="row"><span role="cell" class="bk-f">' + esc(wordOf(kind, x.field)) + '</span>' +
              '<span role="cell" class="bk-now">' + (x.portal ? esc(x.portal) : '<span class="muted">—</span>') + '</span>' +
              '<span role="cell" class="bk-now">' + (x.bukku ? esc(x.bukku) : '<span class="muted">—</span>') + '</span></div>';
          }).join('') + '</div>';
      }
      opts.said = '';
      wire(d);
    }
    function wire(d, linkOnly) {
      var rf = host.querySelector('[data-bk="refresh"]');
      if (rf) rf.addEventListener('click', function () { group(host, kind, id, Object.assign({}, opts, { reread: true })); });
      var ac = host.querySelector('[data-bk="addct"]');
      if (ac) ac.addEventListener('click', function () { var r = READ[kind + ':' + id]; opts.addContact(r && r.values ? r.values.person : ''); });
      var hb = host.querySelector('[data-bk="hold"]');
      if (hb) hb.addEventListener('click', function () {
        var r = READ[kind + ':' + id] || {};
        var names = (r.differs || []).map(function (x) { return wordOf(kind, x.field); });
        window.ADspaceConfirm.ask({
          title: 'Use Bukku\'s details?', go: 'Use Bukku\'s', tone: 'warn', wait: true, opener: hb,
          body: holds(kind) ? 'The portal\'s ' + names.join(', ') + ' will be replaced with Bukku\'s details. From then on, these details are kept in Bukku.'
            : 'The supplier\'s ' + names.join(', ') + ' will be replaced with Bukku\'s details.'
        }, function () {
          return call({ action: 'hold', kind: kind, id: id }).then(function (x) {
            if (x.error) return said(x);
            var took = x.changed || [];
            x.at = Date.now(); x.changed = [];
            READ[kind + ':' + id] = x;
            group(host, kind, id, Object.assign({}, opts, { said: 'Bukku\'s details saved.' }));
            if (opts.read) opts.read(Object.assign({}, x, { changed: took }));
            return '';
          });
        });
      });
      var b = host.querySelector('[data-bk="send"]');
      /* The outcome is said in the band it changed (2026-10-20, BKU-3). */
      if (b) b.addEventListener('click', function () {
        send(kind, id, b, linkOnly, function (r) {
          delete READ[kind + ':' + id];
          group(host, kind, id, Object.assign({}, opts, { said: r && r.action === 'link' ? 'Linked to Bukku.' : 'Sent to Bukku.' }));
          if (opts.after) opts.after();
        });
      });
      var mb = host.querySelector('[data-bk="menu"]');
      if (mb) mb.addEventListener('click', function (e) {
        e.stopPropagation();
        var m = mb.parentNode.querySelector('.kmenu'), open = m.hidden;
        m.hidden = !open; mb.setAttribute('aria-expanded', String(open));
        if (open && window.ADspaceMenu) window.ADspaceMenu.place(mb, m);
      });
      var u = host.querySelector('[data-bk="unlink"]');
      if (u) u.addEventListener('click', function (e) {
        e.stopPropagation();
        u.closest('.kmenu').hidden = true; mb.setAttribute('aria-expanded', 'false');
        unlink(host, kind, id, d, opts, mb);
      });
      if (window.ADspaceActs && window.ADspaceActs.scan) window.ADspaceActs.scan(host);
    }
  }
  /* Unlink asks first: what goes, that Bukku keeps the contact, and that
     a supplier that is also a client goes with it (one Bukku contact). */
  function unlink(host, kind, id, d, opts, opener) {
    var A = window.ADspaceAdmin;
    var code = d.code || String(d.contact_id);
    var noun = kind === 'client' ? 'client' : kind === 'entity' ? 'billing entity' : kind === 'creator' ? 'creator' : kind === 'member' ? 'colleague' : 'supplier';
    window.ADspaceConfirm.ask({
      title: 'Unlink from Bukku?', go: 'Unlink', tone: 'warn', wait: true, opener: opener,
      body: 'This ' + noun + ' will no longer be linked to Bukku contact ' + code + '. Nothing changes in Bukku. ' +
        (reads(kind) ? 'Link to Bukku' : 'Send to Bukku') + ' will then offer the matching contacts again.' + (kind === 'client' || kind === 'supplier' ? ' A supplier that is also a client shares one Bukku contact, so both will be unlinked.' : '')
    }, function () {
      return rpc('bukku_unlink', { p_kind: kind, p_id: id }).then(function (r) {
        if (r.error) return r.error === 'not-linked' ? 'This ' + noun + ' is no longer linked to Bukku. Refresh the page.' : said(r);
        delete READ[kind + ':' + id];
        group(host, kind, id, opts);
        if (opts.after) opts.after();
        if (A && A.undoHere) A.undoHere('Unlinked from Bukku.', function () {
          rpc('bukku_unlink_undo', { p_kind: kind, p_id: id, p_stamp: r.stamp }).then(function (x) {
            delete READ[kind + ':' + id];
            group(host, kind, id, Object.assign({}, opts, { said: x.error ? (x.error === 'moved' ? 'Not restored, as it has since been linked again.' : said(x)) : 'Linked to Bukku again.' }));
            if (!x.error && opts.after) opts.after();
          });
        }, host);
        return '';
      });
    });
  }

  /* ---- Send to Bukku -----------------------------------------------------
     The contact first: the one linked, else a choice among the contacts
     that may be it and a new contact. Then what changes, read again as the
     choice moves. Send links and sends in one press. */
  var sheet = null, cur = null;
  function build() {
    if (sheet) return sheet;
    sheet = document.createElement('div');
    sheet.className = 'sheet'; sheet.id = 'bkSheet'; sheet.hidden = true;
    sheet.innerHTML = '<div class="sheet-card formsheet" role="dialog" aria-modal="true" aria-labelledby="bkTitle" data-narrow="560">' +
      '<div class="sheet-head"><h3 id="bkTitle">Send to Bukku</h3>' +
      '<button class="iconbtn" type="button" data-a="x" aria-label="Close">' + X + '</button></div>' +
      '<div class="sheet-body">' +
        '<section class="fsec"><h4 class="fsec-h" id="bkPickH">Choose a contact in Bukku</h4><div id="bkPick" role="radiogroup" aria-labelledby="bkPickH"></div></section>' +
        '<section class="fsec"><h4 class="fsec-h" id="bkRowsH">Changes</h4><div id="bkRows"></div></section>' +
        '<div class="msg" id="bkMsg" role="status"></div>' +
      '</div>' +
      '<div class="sheet-foot">' +
        '<button class="btn btn-primary" type="button" id="bkGo" disabled>Send</button>' +
        '<button class="btn" type="button" id="bkLink" hidden>Link only</button>' +
        '<button class="btn btn-quiet" type="button" id="bkCancel">Cancel</button>' +
      '</div></div>';
    document.body.appendChild(sheet);
    sheet.querySelector('[data-a="x"]').addEventListener('click', shut);
    $('bkCancel').addEventListener('click', shut);
    $('bkGo').addEventListener('click', function () { go(cur && cur.mode === 'link' && cur.contact ? 'link' : 'send'); });
    /* Link only (2026-10-19): the contact Bukku holds, linked as it stands. */
    $('bkLink').addEventListener('click', function () { go('link'); });
    $('bkPick').addEventListener('change', function (e) {
      if (e.target && e.target.name === 'bkPick') { cur.contact = e.target.value; preview(); }
    });
    return sheet;
  }
  function shut() { if (sheet) sheet.hidden = true; if (window.ADspaceSheet && window.ADspaceSheet.isOpen(sheet)) window.ADspaceSheet.close(); cur = null; }
  function say(text, tone) { var m = $('bkMsg'); if (m) { m.textContent = text || ''; m.className = 'msg' + (text && tone ? ' ' + tone : ''); } }
  var WHY = { brn: 'Same Business Registration No.', name: 'Same name', similar: 'Similar name', job: 'Bill for', client: 'Linked to client' };

  function send(kind, id, btn, only, done) {
    build();
    cur = { kind: kind, id: id, done: done, contact: '', linked: null, seq: 0, only: !!only, mode: reads(kind) || only ? 'link' : 'send' };
    $('bkTitle').textContent = cur.mode === 'link' ? 'Link to Bukku' : 'Send to Bukku';
    $('bkPick').innerHTML = '<p class="muted">Reading Bukku.</p>';
    $('bkRows').innerHTML = '';
    $('bkGo').disabled = true; $('bkGo').textContent = 'Send';
    say('');
    window.ADspaceSheet.show(sheet, { opener: btn });
    var me = cur;
    call({ action: 'find', kind: kind, id: id }).then(function (d) {
      if (cur !== me) return;
      if (d.error) { $('bkPick').innerHTML = ''; say(said(d), 'err'); return; }
      if (d.linked) {
        me.mode = 'send'; $('bkTitle').textContent = 'Send to Bukku';
        me.linked = d.linked; me.contact = String(d.linked.id);
        $('bkPick').innerHTML = '<p class="readfield">' + esc(d.linked.code) + ' · ' + esc(d.linked.name) + '</p>';
      } else {
        var list = d.candidates || [];
        me.contact = list.length ? String(list[0].id) : '';
        $('bkPick').innerHTML = list.map(function (c, n) {
          return '<label class="tickline bk-cand"><input type="radio" name="bkPick" value="' + esc(c.id) + '"' + (n === 0 ? ' checked' : '') + '> ' +
            '<span><b>' + esc(c.code) + ' · ' + esc(c.name) + '</b><span class="muted"> · ' + esc((WHY[c.why] || '') + (c.why === 'job' ? ' ' + c.job : '')) +
            (c.archived ? ' · Archived' : '') + '</span></span></label>';
        /* A supplier whose client is linked is offered that contact
           alone (2026-11-23): one Bukku contact is one company's. */
        }).join('') + (me.only || d.shared ? '' :
          '<label class="tickline bk-cand"><input type="radio" name="bkPick" value=""' + (list.length ? '' : ' checked') + '> ' +
          '<span><b>New contact</b><span class="muted"> · ' + esc(d.next_code || '') + '</span></span></label>');
        /* Linked only, a creator is never made in Bukku from here. */
        if (me.only && !list.length) say('No Bukku contact matches this creator\'s name or a bill for their earlier job IDs. Add an earlier job ID, or approve their payment details.', 'warn');
      }
      preview();
    });
  }
  function preview() {
    var me = cur, seq = ++me.seq;
    $('bkGo').disabled = true;
    /* Linking: an existing contact is linked as Bukku holds it, nothing
       sent, and the record then reads Bukku (what differs waits on a side
       chosen on the band); New contact is made in Bukku from the portal. */
    var linking = me.mode === 'link' && !!me.contact;
    /* A creator with no details: nothing to compare, the contact linked as it is. */
    $('bkRowsH').parentNode.hidden = !!me.only;
    if (me.only) { $('bkGo').textContent = 'Link'; $('bkLink').hidden = true; $('bkRows').innerHTML = ''; $('bkGo').disabled = !me.contact; return; }
    $('bkGo').textContent = linking ? 'Link' : me.mode === 'link' ? 'Create in Bukku' : me.linked || !me.contact ? 'Send' : 'Link and send';
    $('bkLink').hidden = me.mode === 'link' || !!me.linked || !me.contact; $('bkLink').disabled = true;
    $('bkRowsH').textContent = linking ? 'Differences' : 'Changes';
    $('bkRows').innerHTML = '<p class="muted">Reading.</p>';
    say('');
    call({ action: 'preview', kind: me.kind, id: me.id, contact: me.contact || null }).then(function (d) {
      if (cur !== me || seq !== me.seq) return;
      if (d.error) { $('bkRows').innerHTML = ''; say(said(d), 'err'); return; }
      var rows = (d.rows || []).filter(function (r) { return !r.same; });
      $('bkRows').innerHTML = !rows.length ? '<p class="muted">' + (linking ? 'The details match.' : 'Nothing changes.') + '</p>'
        : '<div class="bk-table" role="table"><div class="bk-tr bk-th" role="row"><span role="columnheader">Field</span>' +
            '<span role="columnheader">' + (me.contact ? 'In Bukku' : 'Now') + '</span><span role="columnheader">' + (linking ? 'In the portal' : 'After') + '</span></div>' +
          rows.map(function (r) {
            /* Sending to a contact Bukku holds, each change is ticked to go
               (2026-11-10, the user: "choose which one to send"). */
            var tick = !linking && r.pick && r.key
              ? '<label class="bk-pick"><input type="checkbox" name="bkSend" value="' + esc(r.key) + '" checked aria-label="Send ' + esc(r.field) + '"> ' + esc(r.field) + '</label>'
              : esc(r.field);
            return '<div class="bk-tr" role="row"><span role="cell" class="bk-f">' + tick + '</span>' +
              '<span role="cell" class="bk-now">' + (r.now ? esc(r.now) : '<span class="muted">—</span>') + '</span>' +
              '<span role="cell" class="bk-after">' + (r.after ? esc(r.after) : '<span class="muted">—</span>') + '</span></div>';
          }).join('') + '</div>';
      $('bkGo').disabled = false; $('bkLink').disabled = false;
    });
  }
  function go(action) {
    var me = cur;
    if (!me) return;
    $('bkGo').disabled = true; $('bkLink').disabled = true; say('');
    var skip = Array.prototype.slice.call(document.querySelectorAll('#bkRows input[name="bkSend"]'))
      .filter(function (x) { return !x.checked; }).map(function (x) { return x.value; });
    call({ action: action, kind: me.kind, id: me.id, contact: me.contact || null, skip: skip }).then(function (d) {
      if (cur !== me) return;
      $('bkGo').disabled = false; $('bkLink').disabled = false;
      if (d.error) { say(said(d), 'err'); return; }
      shut();
      if (me.done) me.done(Object.assign({ action: action }, d));
    });
  }

  /* ---- Settings: which Bukku fields hold the IDs ------------------------- */
  var cfg = null;
  function config() {
    return rpc('bukku_config', {}).then(function (d) { cfg = d.error ? null : d; return d; });
  }
  function configLine() {
    return config().then(function (d) {
      /* A refused read reads Could not load. on the row, never nothing;
         each field is said for itself (2026-10-22, SET2-3). */
      if (d.error) throw new Error(d.error);
      /* Cut to the facts that matter (the Settings review, 2026-11-26):
         how many of the ID fields and of the bill and invoice details are
         set; the sheet names each. */
      var F = [d.field_client, d.field_supplier, d.field_creator];
      var B = [d.bill_item_sku, d.bill_class_code, d.bill_account_code, d.budget_account_code, d.campaign_invoice_model];
      var n = function (xs) { return xs.filter(Boolean).length + '\u00a0of\u00a0' + xs.length; };
      return n(F) + ' contact ID fields set · ' + n(B) + ' bill details set';
    });
  }
  function openConfig(btn, sayRow) {
    sayRow = sayRow || function () {};
    Promise.all([config(), call({ action: 'fields' }), call({ action: 'accounts' })]).then(function (a) {
      var c = a[0], f = a[1], ac = a[2] || {};
      if (c.error) { sayRow(said(c), 'err'); return; }
      if (f.error) { sayRow(said(f), 'err'); return; }
      var list = (f.fields || []);
      if (!list.length) { sayRow('Bukku has no custom contact fields. Add Client ID, Supplier ID and Creator ID in Bukku first.', 'err'); return; }
      var choices = [['', 'Not set']].concat(list.map(function (x) { return [String(x.id), x.name]; }));
      /* A creator's bill (CREATOR FEES, 2026-11-13; the KOC fee item
         2026-11-15): the item's SKU, the classification code and the
         account, each found in Bukku by its code when a bill is made. */
      var accts = ac.error ? [] : (ac.accounts || []).filter(function (x) { return x.code; });
      var acctChoices = [['', 'Not set']].concat(accts.map(function (x) { return [x.code, x.code + ' · ' + x.name]; }));
      if (c.bill_account_code && !accts.some(function (x) { return x.code === c.bill_account_code; }))
        acctChoices.push([c.bill_account_code, c.bill_account_name || c.bill_account_code]);
      var budChoices = [['', 'Not set']].concat(accts.map(function (x) { return [x.code, x.code + ' · ' + x.name]; }));
      if (c.budget_account_code && !accts.some(function (x) { return x.code === c.budget_account_code; }))
        budChoices.push([c.budget_account_code, c.budget_account_code]);
      window.ADspaceConfirm.ask({
        title: 'Bukku', go: 'Save', wait: true,
        fields: [
          { name: 'client', head: 'ID fields', label: 'Client ID field', choices: choices, value: c.field_client ? String(c.field_client) : '', required: false },
          { name: 'supplier', label: 'Supplier ID field', choices: choices, value: c.field_supplier ? String(c.field_supplier) : '', required: false },
          { name: 'creator', label: 'Creator ID field', choices: choices, value: c.field_creator ? String(c.field_creator) : '', required: false,
            note: 'If not set, the Creator ID goes in the Supplier ID field.' },
          { name: 'sku', head: 'Creator bills', label: 'Item SKU', value: c.bill_item_sku || '', placeholder: 'P995', required: true },
          { name: 'cls', label: 'Classification code', value: c.bill_class_code || '', placeholder: '037', required: true },
          { name: 'account', label: 'Account', choices: acctChoices, value: c.bill_account_code || '', required: true },
          /* A quotation's advertising budget is invoiced on its own account,
             with no tax (2026-11-17). */
          /* The same select of Bukku's accounts as the bill's (the
             Settings review, 2026-11-26), Not set its first option. */
          { name: 'budget', head: 'Quotation invoices', label: 'Advertising budget account', choices: budChoices, value: c.budget_account_code || '',
            required: false },
          /* A campaign's invoice takes this invoice's product, account and
             tax code (CAMPAIGN INVOICE FROM BUKKU, 2026-11-26). */
          { name: 'model', head: 'Campaign invoices', label: 'Sample invoice number', value: c.campaign_invoice_model || '',
            placeholder: 'AINV000123', required: false }
        ],
        check: function (v) {
          if (v.client && (v.client === v.supplier || v.client === v.creator)) return 'Choose a different field for the Client ID.';
          if (!/^[A-Za-z0-9._\/-]{1,40}$/.test(String(v.sku || '').trim())) return 'Enter the item SKU as it appears in Bukku, for example P995.';
          if (!/^[0-9]{3}$/.test(String(v.cls || '').trim())) return 'Enter the classification code as three digits, for example 037.';
          if (!v.account) return 'Choose the account.';
          if (String(v.budget || '').trim() && !/^[A-Za-z0-9._\/-]{1,30}$/.test(String(v.budget).trim())) return 'Enter the account code as it appears in Bukku, for example 3000-01.';
          if (String(v.model || '').trim() && !/^[A-Za-z0-9._\/-]{3,40}$/.test(String(v.model).trim())) return 'Enter the invoice number as it appears in Bukku, for example AINV000123.';
          return '';
        }
      }, function (v) {
        return rpc('bukku_config_set', { p_client: v.client ? Number(v.client) : null, p_supplier: v.supplier ? Number(v.supplier) : null,
          p_creator: v.creator ? Number(v.creator) : null }).then(function (d) {
          if (d.error) return said(d);
          var sku = String(v.sku || '').trim(), cls = String(v.cls || '').trim(), bud = String(v.budget || '').trim();
          var budget = bud === (c.budget_account_code || '') ? Promise.resolve({}) : rpc('bukku_invoice_set', { p_budget_code: bud || null });
          var mod = String(v.model || '').trim().toUpperCase();
          var model = mod === (c.campaign_invoice_model || '') ? Promise.resolve({}) : rpc('bukku_campaign_model_set', { p_number: mod || null });
          return Promise.all([budget, model]).then(function (both) {
          var db = both[0].error ? both[0] : both[1];
          if (db.error) return said(db);
          if (sku === (c.bill_item_sku || '') && cls === (c.bill_class_code || '') && v.account === (c.bill_account_code || '')) { sayRow('Saved.', 'ok'); return ''; }
          var pick = acctChoices.filter(function (x) { return x[0] === v.account; })[0];
          var hit = accts.filter(function (x) { return x.code === v.account; })[0];
          return rpc('bukku_bill_set', { p_sku: sku, p_class: cls, p_account: hit ? Number(hit.id) : null, p_account_code: v.account,
            p_name: pick ? pick[1] : null }).then(function (d2) {
            if (d2.error) return said(d2);
            sayRow('Saved.', 'ok');
            return '';
          });
          });
        });
      });
    });
  }

  /* Bukku's tax codes (2026-10-22), for the Settings page's Tax codes. */
  function taxes() { return call({ action: 'taxes' }).then(function (d) { return d.error ? { error: said(d) } : d; }); }

  window.ADspaceBukku = { mark: MARK, group: group, send: function (k, i, b, done) { return send(k, i, b, false, done); }, openConfig: openConfig, configLine: configLine, taxes: taxes, said: said,
    held: held, state: state, save: save, fresh: fresh, said: said };
})();
