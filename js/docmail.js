/* Send by email (2026-10-31, 2026-10-31-client-document-emails.sql): a
 * client's quotation, Letter of Offer or client letter emailed to one of its
 * contacts, by hand, beside Send on WhatsApp. Nothing goes by itself.
 *
 *   ADspaceDocMail.may(kind)          whether this colleague may send one
 *                                     (never while Send by email is off in
 *                                     Business settings, `client_email_on`):
 *                                     Clients: Quotations (`quotation`),
 *                                     Clients: Letters (`offer`), Letters or
 *                                     Documents: Client documents (`letter`),
 *                                     each at Work
 *   ADspaceDocMail.compose(o)         the one sheet (#dmSheet): o = { kind,
 *                                     ref, clientId, opener, doc: { title,
 *                                     file() → Promise { blob, name } },
 *                                     onSent(line) }. To is the client's
 *                                     contacts holding an email, the billing
 *                                     contact first; the words the
 *                                     template's, filled by the database and
 *                                     changed here; the PDF drawn here as
 *                                     Download draws it, sent by
 *                                     supplier-mail, which files it before it
 *                                     goes and checks the PDF names the
 *                                     record's reference
 *   ADspaceDocMail.lines(clientId)    a promise of each record's latest email
 *                                     as one line (Emailed 31 Oct 2026 ·
 *                                     Delivered), by its id, read once a
 *                                     visit to the client
 *   ADspaceDocMail.forget(clientId)   the next lines() reads again
 *   ADspaceDocMail.openTemplates(btn) Settings, Templates: Client emails
 *                                     (`team.settings`)
 */
(function () {
  'use strict';
  var API = window.ADspaceAPI;
  var KIND = { quotation: 'Quotation', offer: 'Letter of Offer', letter: 'Client letter' };
  var FIELDS = ['contact name', 'client name', 'company name', 'document title', 'document reference', 'document date', 'valid until', 'sender name'];
  var SAID = {
    denied: 'You do not have permission to send this document. Please ask an admin.',
    'not-found': 'This document is no longer available.',
    'void-quotation': 'A cancelled quotation cannot be sent. Restore it first.',
    void: 'A voided or replaced letter cannot be sent.',
    unreleased: 'Send or publish the quotation first.',
    'no-contact': 'This prospect is marked Do not contact. Allow contact first.',
    'no-file': 'A document added by hand has no letter to send.',
    'no-email': 'None of this client\'s contacts has an email address. Add one in Contacts.',
    'bad-contact': 'Choose a contact with an email address.',
    'bad-subject': 'Enter a subject, 2 to 200 characters.',
    'bad-body': 'Enter the message, 2 to 5,000 characters.',
    'bad-kind': 'Refresh the page and try again.',
    'bad-request': 'Refresh the page and try again.',
    'bad-file': 'The PDF could not be attached. Preview it to check, then try again.',
    sending: 'This email is on its way. Wait a minute before sending again.',
    'mail-not-set-up': 'Email is not set up yet. Please contact an admin.',
    'not-sent': 'Not sent. Try again.',
    'not-confirmed': 'Not confirmed. Check with the client before sending again.',
    'needs-update': 'This feature is not available yet. Please contact an admin.',
    'email-off': 'Send by email is off. Turn it on in Settings, Clients.'
  };
  /* Resend's word on an email, as the record's line reads it. */
  var STATE = { sending: 'Sending', sent: '', delivered: 'Delivered', opened: 'Opened', failed: 'Not sent',
    bounced: 'Bounced', complained: 'Marked as spam', unknown: 'Not confirmed' };

  function db() { return API && API.client; }
  function $(id) { return document.getElementById(id); }
  function esc(s) { return window.ADspaceWords.esc(s); }
  function bridge() { return window.ADspaceAdmin || {}; }
  function mayAt(key, level) { var b = bridge(); return Boolean(b.may && b.may(key, level)); }
  /* Send by email is on (Business settings, `client_email_on`, from a day). */
  function on() {
    var M = window.ADspaceMoney;
    return Boolean(M && M.setting && Number(M.setting('client_email_on', window.ADspaceClock.today())) === 1);
  }
  function may(kind) {
    if (!on()) return false;
    if (kind === 'quotation') return mayAt('clients.quotes', 'work');
    if (kind === 'offer') return mayAt('clients.documents', 'work');
    if (kind === 'letter') return mayAt('clients.documents', 'work') || mayAt('register.documents', 'work');
    return false;
  }
  function said(code, kind) {
    if (code === 'void' && kind === 'quotation') return SAID['void-quotation'];
    return SAID[code] || 'Not sent. Try again.';
  }
  function codeOf(r) {
    if (!r) return 'not-sent';
    if (r.error) return /function|schema cache|does not exist/i.test(String(r.error.message || '')) ? 'needs-update' : (r.error.code && SAID[r.error.code] ? r.error.code : 'not-sent');
    return (r.data && r.data.error) || '';
  }
  function msg(id, text, tone) {
    var el = $(id);
    if (!el) return;
    el.textContent = text || '';
    el.className = 'msg' + (tone ? ' ' + tone : '');
  }
  function day(at) { return window.ADspaceClock.date(at); }

  // ---- The record's line ---------------------------------------------------
  var cache = {};
  function lines(clientId) {
    if (!clientId) return Promise.resolve({});
    if (cache[clientId]) return cache[clientId];
    cache[clientId] = db().rpc('client_emails_of', { p_client: clientId }).then(function (r) {
      var d = r.data || {}, out = {};
      if (r.error || d.error) return out;
      (d.rows || []).forEach(function (e) {
        if (out[e.ref_id]) return;
        var st = STATE[e.status];
        out[e.ref_id] = { status: e.status, line: (e.status === 'failed' ? 'Email not sent ' : 'Emailed ') + day(e.created_at) +
          (st && e.status !== 'failed' ? ' · ' + st : ''), bad: e.status === 'failed' || e.status === 'bounced' || e.status === 'complained' };
      });
      return out;
    }).catch(function () { delete cache[clientId]; return {}; });
    return cache[clientId];
  }
  function forget(clientId) { if (clientId) delete cache[clientId]; else cache = {}; }

  // ---- The sheet -------------------------------------------------------------
  var cx = null;
  function compose(o) {
    var sheet = $('dmSheet');
    if (!sheet || !o || !may(o.kind)) return;
    cx = { o: o, prep: null, filled: null, ask: 0, sending: false };
    $('dmTitle').textContent = 'Send by email';
    msg('dmMsg', '');
    $('dmRecent').hidden = true;
    $('dmTo').innerHTML = '<option value="">Loading…</option>';
    $('dmTo').disabled = true;
    $('dmReply').textContent = '';
    $('dmCcLine').hidden = true;
    $('dmSubject').value = ''; $('dmBody').value = '';
    $('dmAttachName').textContent = o.doc && o.doc.title ? o.doc.title : '';
    $('dmGo').disabled = true;
    window.ADspaceSheet.show(sheet, { opener: o.opener || null });
    prepare(null);
  }
  function prepare(contact) {
    var mine = cx, at = ++cx.ask;
    db().rpc('client_email_prepare', { p_kind: mine.o.kind, p_ref: mine.o.ref, p_contact: contact }).then(function (r) {
      if (cx !== mine || mine.ask !== at) return;
      var code = codeOf(r), d = r.data || {};
      if (code) {
        $('dmTo').innerHTML = '<option value="">No recipient</option>';
        msg('dmMsg', said(code, mine.o.kind), 'err');
        return;
      }
      var was = mine.filled, keepWords = was && ($('dmSubject').value !== was.subject || $('dmBody').value !== was.body);
      mine.prep = d;
      var sel = $('dmTo');
      sel.innerHTML = (d.contacts || []).map(function (k) {
        return '<option value="' + esc(k.id) + '">' + esc(k.name + ' · ' + k.email) + '</option>';
      }).join('');
      sel.value = d.to.id;
      sel.disabled = (d.contacts || []).length < 2;
      $('dmReply').textContent = d.reply_to || (window.ADSPACE_CONFIG || {}).accountEmail || '';
      $('dmCcLine').hidden = !d.cc;
      $('dmCcWord').textContent = 'Copy the finance email' + (d.cc ? ' (' + d.cc + ')' : '');
      /* Words the colleague changed stay as typed when another contact is
         chosen; the template's own follow the contact. */
      if (!keepWords) {
        $('dmSubject').value = d.subject || '';
        $('dmBody').value = d.body || '';
        if (window.ADspaceGrow) window.ADspaceGrow.fit($('dmBody'));
      }
      mine.filled = { subject: $('dmSubject').value, body: $('dmBody').value };
      var rc = $('dmRecent');
      rc.hidden = !d.recent;
      if (d.recent) rc.textContent = 'Emailed ' + day(d.recent.at) + (d.recent.by ? ' by ' + d.recent.by : '') + ' to ' + d.recent.to + '.';
      $('dmGo').disabled = false;
    }).catch(function () {
      if (cx !== mine) return;
      msg('dmMsg', SAID['not-sent'], 'err');
    });
  }
  function preview() {
    if (!cx || !cx.o.doc || !cx.o.doc.file) return;
    var tab = window.ADspaceDocs.previewTab();
    cx.o.doc.file().then(function (f) { return window.ADspaceDocs.save(f.blob, f.name, tab); }).catch(function (e) {
      window.ADspaceDocs.shut(tab);
      msg('dmMsg', 'The PDF could not be generated: ' + ((e && e.message) || e), 'err');
    });
  }
  function b64(bytes) {
    var out = '', i, CH = 0x8000;
    for (i = 0; i < bytes.length; i += CH) out += String.fromCharCode.apply(null, bytes.subarray(i, i + CH));
    return btoa(out);
  }
  function fields() {
    return { subject: $('dmSubject').value.trim(), body: $('dmBody').value.trim(),
      cc: !$('dmCcLine').hidden && $('dmCc').checked, contact: $('dmTo').value || null };
  }
  function ask() {
    var p = cx && cx.prep;
    if (!p || cx.sending) return;
    var f = fields();
    if (f.subject.length < 2) { msg('dmMsg', SAID['bad-subject'], 'err'); $('dmSubject').focus(); return; }
    if (f.body.length < 2) { msg('dmMsg', SAID['bad-body'], 'err'); $('dmBody').focus(); return; }
    var to = (p.contacts || []).filter(function (k) { return k.id === f.contact; })[0] || p.to;
    window.ADspaceConfirm.ask({ title: 'Send email?', go: 'Send',
      body: (cx.o.doc && cx.o.doc.title ? cx.o.doc.title + ' to ' : 'To ') + to.email + (f.cc ? ', a copy to ' + p.cc : '') + '.' },
      function () { send(false); });
  }
  function send(again) {
    var mine = cx;
    if (!mine || mine.sending) return;
    var f = fields(), go = $('dmGo');
    mine.sending = true; go.disabled = true; msg('dmMsg', '');
    var name = '';
    mine.o.doc.file().then(function (file) {
      name = file.name;
      return file.blob.arrayBuffer();
    }).then(function (buf) {
      return db().functions.invoke('supplier-mail', { body: { client: true, kind: mine.o.kind, ref: mine.o.ref, contact: f.contact,
        cc: f.cc, subject: f.subject, body: f.body, again: Boolean(again), pdf: b64(new Uint8Array(buf)), filename: name } });
    }).then(function (r) {
      return API.fnRefusal(r).then(function (code) {
        mine.sending = false; go.disabled = false;
        if (cx !== mine) return;
        if (!code && r.data && r.data.ok) {
          forget(mine.o.clientId);
          window.ADspaceSheet.close();
          if (mine.o.onSent) mine.o.onSent((mine.o.doc.title || 'Document') + ' emailed.');
          return;
        }
        if (code === 'recent') {
          var rc = (r.data && r.data.recent) || {};
          window.ADspaceConfirm.ask({ title: 'Sent recently', tone: 'warn', go: 'Send again',
            body: (mine.o.doc.title || 'This document') + ' was emailed to ' + (rc.to || 'the client') + (rc.at ? ' on ' + day(rc.at) : '') +
              (rc.by ? ' by ' + rc.by : '') + '.' }, function () { send(true); });
          return;
        }
        if (code === 'not-confirmed' || code === 'not-sent') forget(mine.o.clientId);
        msg('dmMsg', said(code || 'not-sent', mine.o.kind), 'err');
      });
    }).catch(function (e) {
      mine.sending = false; go.disabled = false;
      if (cx === mine) msg('dmMsg', 'The PDF could not be generated: ' + ((e && e.message) || e), 'err');
    });
  }
  function shut() { cx = null; }

  // ---- Templates (Settings, Templates: Client emails) ------------------------
  var tpls = null;
  function openTemplates(btn) {
    tpls = { rows: {}, last: 'body' };
    msg('dmTplMsg', '');
    $('dmTplFields').innerHTML = FIELDS.map(function (f) {
      return '<button class="btn btn-sm" type="button" data-f="' + esc(f) + '">{' + esc(f) + '}</button>';
    }).join('');
    $('dmTplSubject').value = ''; $('dmTplBody').value = '';
    window.ADspaceSheet.show($('dmTplSheet'), { opener: btn || null });
    db().rpc('client_email_templates_list').then(function (r) {
      var code = codeOf(r);
      if (code) { msg('dmTplMsg', said(code), 'err'); return; }
      (r.data.rows || []).forEach(function (t) { tpls.rows[t.kind] = { subject: t.subject, body: t.body, was: t.subject + '\n' + t.body }; });
      $('dmTplPick').value = 'quotation';
      $('dmTplPick').dispatchEvent(new Event('change'));
    });
  }
  function tplShow() {
    var t = tpls && tpls.rows[$('dmTplPick').value];
    if (!t) return;
    tpls.on = $('dmTplPick').value;
    $('dmTplSubject').value = t.subject; $('dmTplBody').value = t.body;
    if (window.ADspaceGrow) window.ADspaceGrow.fit($('dmTplBody'));
  }
  function tplKeep() {
    var t = tpls && tpls.rows[tpls.on];
    if (!t) return;
    t.subject = $('dmTplSubject').value; t.body = $('dmTplBody').value;
  }
  function tplSave() {
    if (!tpls) return;
    tplKeep();
    var changed = Object.keys(tpls.rows).filter(function (k) { var t = tpls.rows[k]; return t.subject + '\n' + t.body !== t.was; });
    if (!changed.length) { window.ADspaceSheet.close(); return; }
    var go = $('dmTplGo'); go.disabled = true;
    var next = function (i) {
      if (i >= changed.length) { go.disabled = false; window.ADspaceSheet.close(); return; }
      var k = changed[i], t = tpls.rows[k];
      db().rpc('client_email_template_save', { p_kind: k, p_subject: t.subject.trim(), p_body: t.body.trim() }).then(function (r) {
        var code = codeOf(r);
        if (code) {
          go.disabled = false;
          $('dmTplPick').value = k; $('dmTplPick').dispatchEvent(new Event('change'));
          msg('dmTplMsg', said(code), 'err');
          return;
        }
        t.was = t.subject + '\n' + t.body;
        next(i + 1);
      }).catch(function () { go.disabled = false; msg('dmTplMsg', 'Not saved. Try again.', 'err'); });
    };
    next(0);
  }
  /* What the Settings row holds. */
  function templatesLine() {
    return db().rpc('client_email_templates_list').then(function (r) {
      if (r.error || (r.data && r.data.error)) throw r.error || new Error(r.data.error);
      var n = ((r.data && r.data.rows) || []).length;
      return n + (n === 1 ? ' template' : ' templates');
    });
  }

  function wire() {
    if (!$('dmSheet') || $('dmSheet').__wired) return;
    $('dmSheet').__wired = true;
    $('dmTo').addEventListener('change', function () { if (cx && cx.prep) prepare(this.value || null); });
    $('dmPreview').addEventListener('click', preview);
    $('dmGo').addEventListener('click', ask);
    $('dmCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('dmClose').addEventListener('click', function () { window.ADspaceSheet.close(); });
    new MutationObserver(function () { if ($('dmSheet').hidden) shut(); }).observe($('dmSheet'), { attributes: true, attributeFilter: ['hidden'] });
    $('dmTplPick').addEventListener('change', function () { if (!tpls) return; tplKeep(); tplShow(); });
    $('dmTplGo').addEventListener('click', tplSave);
    $('dmTplCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('dmTplClose').addEventListener('click', function () { window.ADspaceSheet.close(); });
    new MutationObserver(function () { if ($('dmTplSheet').hidden) tpls = null; }).observe($('dmTplSheet'), { attributes: true, attributeFilter: ['hidden'] });
    $('dmTplFields').addEventListener('click', function (e) {
      var b = e.target.closest && e.target.closest('[data-f]');
      if (!b || !tpls) return;
      var el = tpls.last === 'subject' ? $('dmTplSubject') : $('dmTplBody');
      var w = '{' + b.getAttribute('data-f') + '}', at = el.selectionStart == null ? el.value.length : el.selectionStart;
      el.value = el.value.slice(0, at) + w + el.value.slice(el.selectionEnd == null ? at : el.selectionEnd);
      el.focus(); el.selectionStart = el.selectionEnd = at + w.length;
    });
    $('dmTplSubject').addEventListener('focus', function () { if (tpls) tpls.last = 'subject'; });
    $('dmTplBody').addEventListener('focus', function () { if (tpls) tpls.last = 'body'; });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', wire); else wire();

  window.ADspaceDocMail = { may: may, compose: compose, lines: lines, forget: forget, openTemplates: openTemplates,
    templatesLine: templatesLine, KIND: KIND };
})();
