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
 *   ADspaceBukku.group(host, kind, id, opts)  — the record's Bukku group
 *   ADspaceBukku.send(kind, id, btn, done)    — the Send to Bukku sheet
 *   ADspaceBukku.openConfig(btn, say)         — Settings' Bukku sheet
 *   ADspaceBukku.configLine()                 — Settings' Bukku value line
 */
(function () {
  var API = window.ADspaceAPI;
  var X = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>';

  function db() { return API && API.client; }
  function $(id) { return document.getElementById(id); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function day(iso) { return iso && window.ADspaceClock ? window.ADspaceClock.date(iso) : ''; }
  function may(k, l) { var A = window.ADspaceAdmin; return Boolean(A && A.may && A.may(k, l)); }
  function mayWork(kind) { return kind === 'client' ? may('clients.billing', 'work') : may('suppliers', 'work'); }

  var SAID = {
    denied: 'This needs Clients: Billing (a client) or Suppliers (a supplier) at Work.',
    'not-found': 'That record is no longer there.',
    'not-active': 'Approve the supplier before it is sent to Bukku.',
    'bukku-not-set-up': 'Bukku is not connected. Add its token and subdomain to the portal\'s secrets.',
    'bukku-token': 'Bukku refused the portal\'s token. Make a new one in Bukku and replace it in the secrets.',
    'bukku-unreachable': 'Bukku did not answer. Try again in a few minutes.',
    'bukku-gone': 'That contact is no longer in Bukku. Choose another.',
    'no-field': 'Choose Bukku\'s Client ID and Supplier ID fields on the Settings page (Money, Bukku) first.',
    linked: 'This record is already linked to a contact in Bukku. Read the sheet again.',
    'not-filed': 'The contact was sent to Bukku, but the portal did not keep the link. Send again to link it.',
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

  /* ---- The record's group ------------------------------------------------
     Contact (the code and Bukku's name for it, else Not sent), Last sent,
     and whether the portal's details changed since; Send to Bukku at the
     head's right edge for whoever may send. */
  function group(host, kind, id, opts) {
    if (!host) return;
    opts = opts || {};
    var act = mayWork(kind) && opts.can !== false
      /* Words alone, as Send email and Create link are: no act of the
         table carries an arrow (2026-10-20, SUP-8). */
      ? '<button class="btn btn-sm" type="button" data-bk="send">Send to Bukku</button>' : '';
    var head = '<div class="readgroup-head"><h4 class="fsec-h">Bukku</h4>' + act + '</div>';
    host.innerHTML = head + '<p class="muted">Loading.</p>';
    /* What the record lacks is read up front: a record that cannot be sent
       draws no Send, and says what is missing in one line (2026-10-20,
       BKU-1). */
    Promise.all([rpc('bukku_link_get', { p_kind: kind, p_id: id }),
      act ? rpc('bukku_prepare', { p_kind: kind, p_id: id }) : Promise.resolve({})]).then(function (both) {
      var d = both[0], pre = both[1] || {};
      if (d.error === 'denied') { host.hidden = true; return; }
      host.hidden = false;
      var gap = act && pre.error && ['denied', 'failed', 'needs-update'].indexOf(pre.error) < 0 ? said(pre) : '';
      if (gap) head = '<div class="readgroup-head"><h4 class="fsec-h">Bukku</h4></div>';
      if (d.error) { host.innerHTML = head + '<p class="msg err">' + esc(said(d)) + '</p>'; wire(); return; }
      var rows = d.contact_id
        ? [['Contact', esc(d.code || String(d.contact_id))],
           ['Last sent', esc(day(d.sent_at)) + (d.sent_by ? ' <span class="muted">· ' + esc(d.sent_by) + '</span>' : '')],
           ['Since then', d.changed ? 'Details changed' : 'No change']]
        : [['Contact', 'Not sent']];
      host.innerHTML = head + '<dl class="ovfacts">' + rows.map(function (r) {
        return '<div><dt>' + esc(r[0]) + '</dt><dd>' + r[1] + '</dd></div>';
      }).join('') + '</dl>' + (gap ? '<p class="msg warn bk-gap">' + esc(gap) + '</p>' : '') +
        (opts.note ? '<p class="muted bk-note">' + esc(opts.note) + '</p>' : '') +
        (opts.said ? '<p class="msg ok bk-said" role="status">' + esc(opts.said) + '</p>' : '');
      opts.said = '';
      wire();
    });
    function wire() {
      var b = host.querySelector('[data-bk="send"]');
      /* The outcome is said in the group it changed (2026-10-20, BKU-3). */
      if (b) b.addEventListener('click', function () {
        send(kind, id, b, function (d) {
          group(host, kind, id, Object.assign({}, opts, { said: d && d.action === 'link' ? 'Linked to Bukku.' : 'Sent to Bukku.' }));
        });
      });
      if (window.ADspaceActs && window.ADspaceActs.scan) window.ADspaceActs.scan(host);
    }
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
