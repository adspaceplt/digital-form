/* Bukku (2026-10-18; the user: "build API that push the client or supplier
 * details over to Bukku"): a client's billing, or a supplier's details,
 * sent by hand as one Bukku contact through `bukku-sync`. A contact already
 * in Bukku is linked, never made twice: the sheet offers the contacts with
 * the same registration number or name first, else a new one under Bukku's
 * own next code. What changes is shown field by field before it goes. The
 * Client ID and the Supplier ID ride in the Bukku custom fields chosen on
 * the Settings page (Money, Bukku). A supplier linked to a client is the
 * same contact, typed Customer and Supplier.
 *
 *   ADspaceBukku.group(host, kind, id, opts)  — the record's Bukku band, Unlink in its ⋯
 *                                               (kind client, supplier or entity; opts.after on a link's change)
 *   ADspaceBukku.send(kind, id, btn, done)    — the Send to Bukku sheet
 *   ADspaceBukku.openConfig(btn, say)         — Settings' Bukku sheet
 *   ADspaceBukku.configLine()                 — Settings' Bukku value line
 */
(function () {
  var API = window.ADspaceAPI;
  var X = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>';

  function db() { return API && API.client; }
  function $(id) { return document.getElementById(id); }
  function esc(s) { return window.ADspaceWords.esc(s); }
  function day(iso) { return iso && window.ADspaceClock ? window.ADspaceClock.date(iso) : ''; }
  function may(k, l) { var A = window.ADspaceAdmin; return Boolean(A && A.may && A.may(k, l)); }
  function mayWork(kind) { return kind === 'supplier' ? may('suppliers', 'work') : may('clients.billing', 'work'); }

  var SAID = {
    denied: 'This needs Clients: Billing (a client or a billing entity) or Suppliers (a supplier) at Manage.',
    'not-found': 'That record is no longer there.',
    'not-active': 'Approve the supplier before it is sent to Bukku.',
    'bukku-not-set-up': 'Bukku is not connected. Add its token and subdomain to the portal\'s secrets.',
    'bukku-token': 'Bukku refused the portal\'s token. Make a new one in Bukku and replace it in the secrets.',
    'bukku-unreachable': 'Bukku did not answer. Try again in a few minutes.',
    'bukku-gone': 'That contact is no longer in Bukku. Choose another.',
    'no-field': 'Choose Bukku\'s Client ID and Supplier ID fields on the Settings page (Money, Bukku) first.',
    linked: 'This record is already linked to a contact in Bukku. Read the sheet again.',
    taken: 'That Bukku contact is linked to another record in the portal. Choose another.',
    'not-filed': 'The contact was sent to Bukku, but the portal did not keep the link. Send again to link it.',
    moved: 'Not restored. It was linked again meanwhile.',
    'needs-update': 'This needs a database update.',
    'bad-value': 'Choose a field from the list.',
    failed: 'The request failed. Try again.'
  };
  function said(d) {
    if (!d) return SAID.failed;
    if (d.error === 'incomplete') return 'Fill in ' + (d.missing || []).join(' and ') + ' before it is sent to Bukku.';
    if (d.error === 'bukku-refused') return 'Bukku refused it' + (d.message ? ': ' + d.message : '.');
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

  /* ---- The record's band -------------------------------------------------
     One shaded band at the foot of the details it sends (2026-10-29; the
     user: the group "looks incomplete … simply added"): Bukku, the contact's
     code and its state (Up to date, Details changed, Not linked), Last sent
     under it, and at the right edge Send to Bukku and a ⋯ holding Unlink.
     Unlink lets go of the link alone, nothing changed in Bukku, with Undo
     where it happened, so a record linked to the wrong contact is never a
     dead end. */
  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>';
  function group(host, kind, id, opts) {
    if (!host) return;
    opts = opts || {};
    var work = mayWork(kind) && opts.can !== false;
    host.classList.add('bk-band');
    host.innerHTML = '<div class="bk-l"><b class="bk-t">Bukku</b><span class="muted">Loading.</span></div>';
    /* What the record lacks is read up front: a record that cannot be sent
       draws no Send, and says what is missing in one line (2026-10-20,
       BKU-1). */
    Promise.all([rpc('bukku_link_get', { p_kind: kind, p_id: id }),
      work ? rpc('bukku_prepare', { p_kind: kind, p_id: id }) : Promise.resolve({})]).then(function (both) {
      var d = both[0], pre = both[1] || {};
      if (d.error === 'denied') { host.hidden = true; return; }
      host.hidden = false;
      if (d.error) { host.innerHTML = '<div class="bk-l"><b class="bk-t">Bukku</b></div><p class="msg err bk-sub">' + esc(said(d)) + '</p>'; return; }
      var gap = work && pre.error && ['denied', 'failed', 'needs-update'].indexOf(pre.error) < 0 ? said(pre) : '';
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
      var acts = (work && !gap ? '<button class="btn btn-sm" type="button" data-bk="send">Send to Bukku</button>' : '') +
        (work && linked && !via ? '<span class="team-act"><button class="kmenu-btn" type="button" data-bk="menu" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
          '<div class="kmenu" hidden><button class="kmenu-item" type="button" role="menuitem" data-g="5" data-bk="unlink">Unlink</button></div></span>' : '');
      host.innerHTML = '<div class="bk-l"><b class="bk-t">Bukku</b>' + (linked ? '<span class="bk-code">' + esc(d.code || String(d.contact_id)) + '</span>' : '') + state + '</div>' +
        (via ? '<p class="bk-sub">Linked through ' + esc(via) + '</p>'
          : linked ? '<p class="bk-sub">Last sent ' + esc(day(d.sent_at)) + (d.sent_by ? ' by ' + esc(d.sent_by) : '') + '</p>' : '') +
        (acts ? '<div class="bk-acts">' + acts + '</div>' : '') +
        (gap ? '<p class="msg warn bk-gap">' + esc(gap) + '</p>' : '') +
        (opts.note ? '<p class="muted bk-note">' + esc(opts.note) + '</p>' : '') +
        (opts.said ? '<p class="msg ok bk-said" role="status">' + esc(opts.said) + '</p>' : '');
      opts.said = '';
      wire(d);
    });
    function wire(d) {
      var b = host.querySelector('[data-bk="send"]');
      /* The outcome is said in the band it changed (2026-10-20, BKU-3). */
      if (b) b.addEventListener('click', function () {
        send(kind, id, b, function (r) {
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
    window.ADspaceConfirm.ask({
      title: 'Unlink from Bukku?', go: 'Unlink', tone: 'warn', wait: true, opener: opener,
      body: 'This ' + (kind === 'client' ? 'client' : kind === 'entity' ? 'billing entity' : 'supplier') + ' stops pointing at Bukku contact ' + code + '. Nothing changes in Bukku. ' +
        'Send to Bukku then offers the matching contacts again.' + (kind === 'entity' ? '' : ' A supplier that is also a client shares one Bukku contact, so both are unlinked.')
    }, function () {
      return rpc('bukku_unlink', { p_kind: kind, p_id: id }).then(function (r) {
        if (r.error) return r.error === 'not-linked' ? 'This record is no longer linked. Read it again.' : said(r);
        group(host, kind, id, opts);
        if (opts.after) opts.after();
        if (A && A.undoHere) A.undoHere('Unlinked from Bukku.', function () {
          rpc('bukku_unlink_undo', { p_kind: kind, p_id: id, p_stamp: r.stamp }).then(function (x) {
            group(host, kind, id, Object.assign({}, opts, { said: x.error ? (x.error === 'moved' ? 'Not restored. It was linked again meanwhile.' : said(x)) : 'Linked to Bukku again.' }));
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
        '<section class="fsec"><h4 class="fsec-h" id="bkPickH">Contact in Bukku</h4><div id="bkPick" role="radiogroup" aria-labelledby="bkPickH"></div></section>' +
        '<section class="fsec"><h4 class="fsec-h">What changes</h4><div id="bkRows"></div></section>' +
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
    $('bkGo').addEventListener('click', function () { go('send'); });
    /* Link only (2026-10-19): the contact Bukku holds, linked as it stands. */
    $('bkLink').addEventListener('click', function () { go('link'); });
    $('bkPick').addEventListener('change', function (e) {
      if (e.target && e.target.name === 'bkPick') { cur.contact = e.target.value; preview(); }
    });
    return sheet;
  }
  function shut() { if (sheet) sheet.hidden = true; if (window.ADspaceSheet && window.ADspaceSheet.isOpen(sheet)) window.ADspaceSheet.close(); cur = null; }
  function say(text, tone) { var m = $('bkMsg'); if (m) { m.textContent = text || ''; m.className = 'msg' + (text && tone ? ' ' + tone : ''); } }
  var WHY = { brn: 'Same registration no.', name: 'Same name', similar: 'Similar name' };

  function send(kind, id, btn, done) {
    build();
    cur = { kind: kind, id: id, done: done, contact: '', linked: null, seq: 0 };
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
        me.linked = d.linked; me.contact = String(d.linked.id);
        $('bkPick').innerHTML = '<p class="readfield">' + esc(d.linked.code) + ' · ' + esc(d.linked.name) + '</p>';
      } else {
        var list = d.candidates || [];
        me.contact = list.length ? String(list[0].id) : '';
        $('bkPick').innerHTML = list.map(function (c, n) {
          return '<label class="tickline bk-cand"><input type="radio" name="bkPick" value="' + esc(c.id) + '"' + (n === 0 ? ' checked' : '') + '> ' +
            '<span><b>' + esc(c.code) + ' · ' + esc(c.name) + '</b><span class="muted"> · ' + esc(WHY[c.why] || '') +
            (c.archived ? ' · Archived' : '') + '</span></span></label>';
        }).join('') +
          '<label class="tickline bk-cand"><input type="radio" name="bkPick" value=""' + (list.length ? '' : ' checked') + '> ' +
          '<span><b>New contact</b><span class="muted"> · ' + esc(d.next_code || '') + '</span></span></label>';
      }
      preview();
    });
  }
  function preview() {
    var me = cur, seq = ++me.seq;
    $('bkGo').disabled = true;
    $('bkGo').textContent = me.linked || !me.contact ? 'Send' : 'Link and send';
    $('bkLink').hidden = !!me.linked || !me.contact; $('bkLink').disabled = true;
    $('bkRows').innerHTML = '<p class="muted">Reading.</p>';
    say('');
    call({ action: 'preview', kind: me.kind, id: me.id, contact: me.contact || null }).then(function (d) {
      if (cur !== me || seq !== me.seq) return;
      if (d.error) { $('bkRows').innerHTML = ''; say(said(d), 'err'); return; }
      var rows = (d.rows || []).filter(function (r) { return !r.same; });
      $('bkRows').innerHTML = !rows.length ? '<p class="muted">Nothing changes.</p>'
        : '<div class="bk-table" role="table"><div class="bk-tr bk-th" role="row"><span role="columnheader">Field</span>' +
            '<span role="columnheader">' + (me.contact ? 'In Bukku' : 'Now') + '</span><span role="columnheader">After</span></div>' +
          rows.map(function (r) {
            return '<div class="bk-tr" role="row"><span role="cell" class="bk-f">' + esc(r.field) + '</span>' +
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
    call({ action: action, kind: me.kind, id: me.id, contact: me.contact || null }).then(function (d) {
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
      if (d.field_client && d.field_supplier) return 'Client ID and Supplier ID fields';
      var nb = function (a, b) { return [a, b].map(function (x) { return x.replace(/ /g, '\u00a0'); }).join(' · '); };
      if (d.field_client) return nb('Client ID field', 'Supplier ID not chosen');
      if (d.field_supplier) return nb('Supplier ID field', 'Client ID not chosen');
      return 'Not chosen';
    });
  }
  function openConfig(btn, sayRow) {
    sayRow = sayRow || function () {};
    Promise.all([config(), call({ action: 'fields' })]).then(function (a) {
      var c = a[0], f = a[1];
      if (c.error) { sayRow(said(c), 'err'); return; }
      if (f.error) { sayRow(said(f), 'err'); return; }
      var list = (f.fields || []);
      if (!list.length) { sayRow('Bukku holds no custom contact fields. Add Client ID and Supplier ID in Bukku first.', 'err'); return; }
      var choices = [['', 'Not set']].concat(list.map(function (x) { return [String(x.id), x.name]; }));
      window.ADspaceConfirm.ask({
        title: 'Bukku', go: 'Save', wait: true,
        body: 'The Bukku contact fields that hold the Client ID and the Supplier ID.',
        fields: [
          { name: 'client', label: 'Client ID field', choices: choices, value: c.field_client ? String(c.field_client) : '', required: false },
          { name: 'supplier', label: 'Supplier ID field', choices: choices, value: c.field_supplier ? String(c.field_supplier) : '', required: false }
        ],
        check: function (v) { return v.client && v.client === v.supplier ? 'Choose two different fields.' : ''; }
      }, function (v) {
        return rpc('bukku_config_set', { p_client: v.client ? Number(v.client) : null, p_supplier: v.supplier ? Number(v.supplier) : null }).then(function (d) {
          if (d.error) return said(d);
          sayRow('Saved.', 'ok');
          return '';
        });
      });
    });
  }

  /* Bukku's tax codes (2026-10-22), for the Settings page's Tax codes. */
  function taxes() { return call({ action: 'taxes' }).then(function (d) { return d.error ? { error: said(d) } : d; }); }

  window.ADspaceBukku = { group: group, send: send, openConfig: openConfig, configLine: configLine, taxes: taxes };
})();
