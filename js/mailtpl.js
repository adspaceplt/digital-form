/* Email templates (2026-11-10; the overnight Settings review): every email
 * wording the portal sends, one editor for all of them, each recipient's
 * templates opened from the one section whose emails they are (2026-11-24,
 * the user: "deduplicate every sections"): Edit email templates in the
 * command bar's ⋯ of Clients, Suppliers, Creators, Team's Hiring tab
 * (Candidates) and Messages' Email tab (Sign-in and codes), never from
 * Settings and never from two places.
 *
 *   ADspaceMailTpl.open(btn, say, rec)   one recipient's templates
 *   ADspaceMailTpl.may(rec)              whether the reader may open them
 *   a button carrying `data-mailtpl="{rec}"` opens them at its press
 *
 * The words stay where each sender reads them (supplier_email_templates,
 * client_email_templates, email_templates, the two invoice tables,
 * creator_email_templates, code_email_template): each template saves
 * through its own function,
 * which refuses a field its sender cannot fill (template_check). The fields
 * a template may hold are the database's (template_fields_all), shown as
 * chips that insert at the caret; one typed that is not among them is
 * marked as it is typed, in the field and in the preview beside it. */
(function () {
  'use strict';
  function cli() { return window.ADspaceAPI && window.ADspaceAPI.client; }
  function $(id) { return document.getElementById(id); }
  var esc = function (s) { return window.ADspaceWords.esc(s); };
  var L = function () { return window.ADspaceWords.line; };

  var NOT_YET = window.ADspaceWords.line.notYet;
  var SAID = {
    denied: 'You do not have permission to change these templates. Please ask an admin.',
    'bad-subject': window.ADspaceWords.line.subject,
    'bad-body': window.ADspaceWords.line.message,
    'bad-name': 'Enter a template name of 2 to 80 characters.',
    taken: 'A template of this name already exists. Choose another name.',
    'bad-email': 'Enter a valid email address for the finance team.',
    'no-invoices': 'Keep {invoices} in the message, where the table of invoices goes.',
    'too-long': 'Keep the legal note and the disclaimer to 1,000 characters each.',
    'not-found': 'This template no longer exists.',
    'foot-long': 'Keep the fine print to 1,000 characters.',
    'no-code': 'Keep {code} in the message, where the code goes.',
    'code-in-subject': 'Take {code} out of the subject. A phone shows the subject on its lock screen.',
    'bad-button': 'Enter a button label of 2 to 40 characters.'
  };
  /* The candidate emails (CANDIDATE EMAILS, 2026-11-21): each an automatic
     email with its own switch, hiring-mail's words before they were
     editable. */
  var HM_WORD = { invite: 'Interview invitation', confirm: 'Interview confirmed', rescheduled: 'Interview time changed', cancelled: 'Interview cancelled',
    held: 'Thank you for your interview', moved: 'Decision date changed', pool: 'Talent pool', not: 'Application unsuccessful',
    doc: 'Employment document', doc_again: 'Employment document sent again', confirmed: 'Document confirmed', expired: 'Document expired' };
  /* The two Supabase sends: their words are set in Supabase's dashboard
     (docs/SIGN-IN-EMAILS.md), so they are listed and never edited here. */
  var SUPABASE = [['Sign-in code', 'Your ADspace sign-in code'],
    ['Invitation', 'Welcome to your ADspace Client Portal · Your access to the ADspace Digital Portal']];
  var CM_WORD = { received: 'Details received', review: 'Details to review', approved: 'Details approved', changed: 'Details changed',
    request: 'Payment request', posted: 'Post recorded', paid: 'Payment sent' };

  function may(key) { var A = window.ADspaceAdmin; return Boolean(A && A.may && A.may(key, 'work')); }
  function full(sec) { var A = window.ADspaceAdmin; return Boolean(A && A.may && A.may(sec, 'manage')); }
  function biz() { return may('team.settings'); }
  /* A supplier's emails answer one rule (2026-11-10): Suppliers Full Access
     or Business settings, as email_template_may holds it. */
  function sup() { return full('suppliers') || biz(); }
  function canAdd(rec) { return rec === 'suppliers' ? sup() : rec === 'clients' ? biz() : false; }
  /* Who opens a recipient's templates: a supplier's at Suppliers Full
     Access or Business settings, every other at Business settings. */
  function mayRec(rec) { return rec === 'suppliers' ? sup() : biz(); }
  /* A client's feedback request (2026-11-24): each form in English and
     Chinese, its subject, message and button (feedback_email_templates). */
  var FB_WORD = { quick: 'Service rating', review: 'Performance review' };
  var LANG_WORD = { en: 'English', zh: '中文' };

  /* One read of a list; a refusal or a missing function is null, so a
     recipient whose part the reader may not open is left out. */
  function rpc(fn, args) {
    return cli().rpc(fn, args || {}).then(function (r) {
      if (r.error) throw new Error(/function|schema cache|does not exist/i.test(String(r.error.message || '')) ? NOT_YET : r.error.message);
      return r.data || {};
    });
  }
  function soft(p) { return p.then(function (d) { return d && !d.error ? d : null; }).catch(function () { return null; }); }

  /* What a save answered, in the team's words. */
  function said(d) {
    if (!d || !d.error) return '';
    if (d.error === 'unknown-field') return L().unknownField(d.field, d.fields);
    return SAID[d.error] || 'Not saved.';
  }
  function saveWith(fn, args) {
    return rpc(fn, args).then(said).catch(function (e) { return (e && e.message) || 'Not saved.'; });
  }

  var st = { rec: 'clients', items: [], fields: {}, say: null, opener: null, wired: false, ed: null };

  /* Every template of the recipient open, each with how it is edited and
     saved: only that recipient's lists are read. */
  function load() {
    var r = st.rec;
    var on = function (want, ok, fn) { return r === want && ok ? soft(rpc(fn)) : null; };
    return Promise.all([
      soft(rpc('template_fields_all')),
      on('clients', biz(), 'client_email_templates_list'),
      on('clients', biz(), 'invoice_email_template_get'),
      on('clients', biz(), 'invoice_send_template_get'),
      (r === 'clients' || r === 'suppliers') && canAdd(r) ? soft(rpc('email_templates_list')) : null,
      on('suppliers', sup(), 'supplier_email_templates_list'),
      on('creators', biz(), 'creator_email_templates_get'),
      on('codes', biz(), 'code_email_template_get'),
      on('candidates', biz(), 'hiring_email_templates_get'),
      on('clients', biz(), 'feedback_email_templates_get')
    ]).then(function (a) {
      st.fields = a[0] || {};
      var out = [];
      var CK = { quotation: 'Quotation', offer: 'Letter of Offer', letter: 'Client letter' };
      ((a[1] && a[1].rows) || []).forEach(function (t) {
        out.push({ id: 'client:' + t.kind, rec: 'clients', sec: 'Client documents', name: CK[t.kind] || t.kind, kind: 'client',
          subject: t.subject, body: t.body,
          save: function (v) { return saveWith('client_email_template_save', { p_kind: t.kind, p_subject: v.subject, p_body: v.body }); } });
      });
      [[a[2], 'overdue', 'Overdue reminder', 'invoice_email_template_save'], [a[3], 'invoice', 'Invoice email', 'invoice_send_template_save']].forEach(function (x) {
        var t = x[0];
        if (!t) return;
        out.push({ id: 'invoice:' + x[1], rec: 'clients', sec: 'Invoices', name: x[2], kind: 'invoice', two: true,
          subject: t.subject_one, subject2: t.subject_many, body: t.body, legal: t.legal || '', disclaimer: t.disclaimer || '',
          save: function (v) {
            return saveWith(x[3], { p_subject_one: v.subject, p_subject_many: v.subject2, p_body: v.body, p_legal: v.legal, p_disclaimer: v.disclaimer });
          } });
      });
      ((a[9] && a[9].rows) || []).forEach(function (t) {
        out.push({ id: 'feedback:' + t.kind + ':' + t.lang, rec: 'clients', sec: 'Feedback',
          name: (FB_WORD[t.kind] || t.kind) + ' (' + (LANG_WORD[t.lang] || t.lang) + ')', kind: 'feedback', btn: true,
          subject: t.subject, body: t.body, button: t.button,
          save: function (v) {
            return saveWith('feedback_email_template_save', { p_kind: t.kind, p_lang: t.lang, p_subject: v.subject, p_body: v.body, p_button: v.button });
          } });
      });
      ((a[4] && a[4].rows) || []).forEach(function (t) {
        var to = t.audience === 'supplier' ? 'suppliers' : 'clients';
        if (to === r) out.push(free(t));
      });
      var SK = { approved: 'Supplier approved', document: 'Document' };
      ((a[5] && a[5].rows) || []).forEach(function (t) {
        out.push({ id: 'supplier:' + t.purpose, rec: 'suppliers', sec: 'Supplier emails', name: SK[t.purpose] || t.purpose, kind: 'supplier',
          subject: t.subject, body: t.body,
          save: function (v) { return saveWith('supplier_email_template_save', { p_purpose: t.purpose, p_subject: v.subject, p_body: v.body }); } });
      });
      ((a[6] && a[6].rows) || []).forEach(function (t) {
        var booking = /^(request|posted|paid)$/.test(t.purpose);
        out.push({ id: 'creator:' + t.purpose, rec: 'creators', sec: booking ? 'Payments' : 'Payment details', name: CM_WORD[t.purpose] || t.purpose,
          kind: booking ? 'creator-booking' : 'creator-details', sw: true, on: Boolean(t.on), to: t.purpose === 'review', toEmail: t.to_email || '',
          subject: t.subject, body: t.body,
          save: function (v) {
            return saveWith('creator_email_templates_save', { p_rows: [{ purpose: t.purpose, on: v.on, subject: v.subject, body: v.body,
              to_email: t.purpose === 'review' ? v.to : null }] });
          } });
      });
      ((a[8] && a[8].rows) || []).forEach(function (t) {
        out.push({ id: 'candidate:' + t.kind, rec: 'candidates', sec: /^(doc|doc_again|confirmed|expired)$/.test(t.kind) ? 'Offers and contracts' : 'Interviews and outcomes',
          name: HM_WORD[t.kind] || t.kind, kind: 'candidate', sw: true, on: Boolean(t.on), subject: t.subject, body: t.body,
          save: function (v) { return saveWith('hiring_email_templates_save', { p_rows: [{ kind: t.kind, on: v.on, subject: v.subject, body: v.body }] }); } });
      });
      if (a[7]) {
        var c = a[7];
        out.push({ id: 'code:verify', rec: 'codes', sec: 'Codes', name: 'Verification code', kind: 'code', fine: true,
          subject: c.subject, body: c.body, foot: c.foot || '',
          save: function (v) { return saveWith('code_email_template_save', { p_subject: v.subject, p_body: v.body, p_foot: v.foot }); } });
        SUPABASE.forEach(function (x, n) {
          out.push({ id: 'supabase:' + n, rec: 'codes', sec: 'Standard emails', name: x[0], subject: x[1], fixed: true });
        });
      }
      st.free = Boolean(a[4]);
      st.items = out;
      return out;
    });
  }
  function free(t) {
    return { id: 'free:' + t.id, rec: t.audience === 'supplier' ? 'suppliers' : 'clients', sec: 'New email', name: t.name, kind: 'free', named: true,
      tid: t.id, subject: t.subject, body: t.body,
      save: function (v) { return saveWith('email_template_save', { p_id: t.id, p_audience: t.audience, p_name: v.name, p_subject: v.subject, p_body: v.body }); } };
  }

  /* ---- The list ---------------------------------------------------------- */
  function msg(text, tone) { var m = $('mtMsg'); if (m) { m.textContent = text || ''; m.className = 'msg' + (tone ? ' ' + tone : ''); } }
  var PEN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 20h4L19 9l-4-4L4 16v4Z"/></svg>';
  var PLUS = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>';
  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>';

  function paint() {
    var box = $('mtList');
    var mine = st.items.filter(function (i) { return i.rec === st.rec; });
    var secs = [];
    mine.forEach(function (i) { if (secs.indexOf(i.sec) < 0) secs.push(i.sec); });
    if (st.free && canAdd(st.rec) && secs.indexOf('New email') < 0) secs.push('New email');
    if (!secs.length) { box.innerHTML = '<p class="emptyline">No templates.</p>'; return; }
    box.innerHTML = secs.map(function (s) {
      var rows = mine.filter(function (i) { return i.sec === s; });
      var add = s === 'New email' && st.free && canAdd(st.rec);
      return '<section class="mt-sec"><div class="mt-sec-head"><h4 class="fsec-h">' + esc(s) + '</h4>' +
        (add ? '<button class="btn btn-sm" type="button" data-a="add">' + PLUS + 'Add template</button>' : '') + '</div>' +
        (rows.length ? '<div class="stg-card mt-card">' + rows.map(rowHtml).join('') + '</div>'
          : '<p class="emptyline">No templates.</p>') + '</section>';
    }).join('');
  }
  function rowHtml(i) {
    var meta = i.sw && !i.on ? 'Off' : i.subject;
    return '<div class="stg-row mt-row" data-id="' + esc(i.id) + '">' +
      '<div class="stg-what"><p class="stg-name">' + esc(i.name) + '</p><p class="stg-meta mt-subj">' + esc(meta) + '</p></div>' +
      '<div class="stg-ctl">' +
        (i.kind === 'free' ? '<span class="team-act"><button class="kmenu-btn" type="button" data-a="menu" aria-label="More actions for ' + esc(i.name) + '" aria-expanded="false">' + DOTS + '</button>' +
          '<div class="kmenu" data-menu hidden role="menu"><button class="kmenu-item is-danger" data-g="6" type="button" role="menuitem" data-a="delete">Delete</button></div></span>' : '') +
        (i.fixed ? '' : '<button class="btn btn-sm" type="button" data-a="edit" aria-label="Edit ' + esc(i.name) + '">' + PEN + 'Edit</button>') + '</div></div>';
  }
  function shutMenus() {
    Array.prototype.forEach.call(document.querySelectorAll('#mtList .kmenu'), function (m) { m.hidden = true; });
    Array.prototype.forEach.call(document.querySelectorAll('#mtList [data-a="menu"]'), function (b) { b.setAttribute('aria-expanded', 'false'); });
  }

  function showList(focusId) {
    window.ADspaceSheet.show($('mtSheet'), { opener: st.opener });
    paint();
    var b = focusId && document.querySelector('#mtList .mt-row[data-id="' + focusId + '"] [data-a="edit"]');
    if (b) b.focus({ preventScroll: true });
  }
  /* `rec` is the section's recipient: its templates alone. */
  function open(btn, say, rec) {
    wire();
    st.opener = btn || null; st.say = say || null;
    st.rec = rec || st.rec;
    st.items = [];
    msg('');
    window.ADspaceSheet.show($('mtSheet'), { opener: st.opener });
    var box = $('mtList');
    if (window.ADspaceState && window.ADspaceState.skeleton) window.ADspaceState.skeleton(box, 3);
    load().then(paint).catch(function (e) {
      if (window.ADspaceState && window.ADspaceState.failLine) window.ADspaceState.failLine(box, 'Email templates', (e && e.message) || '', function () { open(btn, say, rec); });
    });
  }

  /* ---- The editor -------------------------------------------------------- */
  var KIND_FIELDS = { feedback: 'feedback', client: 'client', invoice: 'invoice', free: 'free', supplier: 'supplier', 'creator-details': 'creator-details', 'creator-booking': 'creator-booking', code: 'code', candidate: 'candidate' };
  function fieldsOf(kind) { return st.fields[KIND_FIELDS[kind]] || []; }
  var last = null;

  function edit(item, btn) {
    var it = item || { id: '', rec: st.rec, kind: 'free', named: true, isNew: true, name: '', subject: '', body: '' };
    st.ed = it;
    var f = fieldsOf(it.kind);
    $('mtEdTitle').textContent = it.isNew ? 'Add template' : it.name;
    var h = '';
    if (it.named) h += box('name', 'Template name', it.name, 'input');
    if (it.sw) h += '<div class="mt-on"><span class="field-label" id="mtOnL">Send this email</span>' +
      '<button class="switch" type="button" role="switch" id="mtOn" aria-labelledby="mtOnL" aria-checked="' + (it.on ? 'true' : 'false') + '"></button></div>';
    if (it.to) h += box('to', 'Finance email', it.toEmail, 'email', 'Receives Details to review and Payment request.');
    h += box('subject', it.two ? 'Subject for one invoice' : 'Subject', it.subject, 'input');
    if (it.two) h += box('subject2', 'Subject for several invoices', it.subject2, 'input');
    h += box('body', 'Message', it.body, 'area');
    if (it.btn) h += box('button', 'Button', it.button, 'input');
    h += '<div class="mt-chips" role="group" aria-label="Insert a field">' + f.map(function (x) {
      return '<button class="btn btn-sm mt-chip" type="button" data-f="' + esc(x) + '">{' + esc(x) + '}</button>';
    }).join('') + '</div><p class="msg warn mt-odd" id="mtOdd" role="status" hidden></p>';
    if (it.kind === 'invoice') h += box('legal', 'Legal note', it.legal, 'area3') + box('disclaimer', 'Disclaimer', it.disclaimer, 'area3');
    if (it.fine) h += box('foot', 'Fine print', it.foot, 'area3');
    $('mtEdForm').innerHTML = h;
    if (window.ADspaceForm && window.ADspaceForm.scan) window.ADspaceForm.scan($('mtEdForm'));
    $('mtEdMsg').textContent = ''; $('mtEdMsg').className = 'msg';
    last = $('mt-body');
    preview();
    window.ADspaceSheet.show($('mtEdSheet'), { opener: btn || null });
  }
  function box(name, label, value, type, note) {
    var id = 'mt-' + name;
    var ctl = type === 'area' || type === 'area3'
      ? '<textarea class="textarea" id="' + id + '" rows="' + (type === 'area3' ? 3 : 10) + '"' + (type === 'area3' ? '' : ' aria-required="true"') + '>' + esc(value || '') + '</textarea>'
      : type === 'email'
        ? '<input class="input" type="email" id="' + id + '" value="' + esc(value || '') + '" aria-required="true"' + (note ? ' aria-describedby="' + id + 'N"' : '') + '>'
        : '<textarea class="input" data-oneline id="' + id + '" rows="1" aria-required="true">' + esc(value || '') + '</textarea>';
    return '<div class="row"><label class="field-label" for="' + id + '">' + label + '</label>' + ctl +
      (note ? '<p class="asknote" id="' + id + 'N">' + note + '</p>' : '') + '</div>';
  }
  function val(name) { var el = $('mt-' + name); return el ? String(el.value || '').trim() : ''; }

  /* The fields typed that the sender cannot fill, as the database reads
     them: braces, the name lower case with its spaces run together. */
  function odd(text, list) {
    var out = [], re = /\{\s*([^{}]*?)\s*\}/g, m;
    while ((m = re.exec(text || ''))) {
      var k = m[1].toLowerCase().replace(/\s+/g, ' ');
      if (list.indexOf(k) < 0 && out.indexOf('{' + m[1] + '}') < 0) out.push('{' + m[1] + '}');
    }
    return out;
  }
  var TEXTS = ['subject', 'subject2', 'body', 'button', 'legal', 'disclaimer', 'foot'];
  function texts() { return TEXTS.map(val).join('\n'); }
  function marked(text, list) {
    return esc(text).replace(/\{\s*([^{}]*?)\s*\}/g, function (all, k) {
      var ok = list.indexOf(k.toLowerCase().replace(/\s+/g, ' ')) >= 0;
      return '<span class="mt-f' + (ok ? '' : ' is-bad') + '">' + all + '</span>';
    });
  }
  function preview() {
    var it = st.ed, list = fieldsOf(it.kind);
    var bad = odd(texts(), list);
    var o = $('mtOdd');
    o.hidden = !bad.length;
    o.textContent = bad.length ? L().unknownField(bad[0], list) : '';
    TEXTS.forEach(function (n) {
      var el = $('mt-' + n);
      if (el) el.setAttribute('aria-invalid', String(odd(el.value, list).length > 0));
    });
    var paras = val('body').split(/\n{2,}/).filter(Boolean);
    $('mtPreview').innerHTML = '<div class="inv-mail-card">' +
      '<p class="mt-pv-subj">' + (val('subject') ? marked(val('subject'), list) : '<span class="mt-pv-none">No subject</span>') + '</p>' +
      (paras.length ? paras.map(function (p) { return '<p>' + marked(p, list).replace(/\n/g, '<br>') + '</p>'; }).join('') : '<p class="mt-pv-none">No message</p>') +
      (val('button') ? '<p class="mt-pv-btn"><span>' + marked(val('button'), list) + '</span></p>' : '') +
      (val('legal') ? '<p class="mt-pv-fine">' + marked(val('legal'), list) + '</p>' : '') +
      (val('disclaimer') ? '<p class="mt-pv-fine">' + marked(val('disclaimer'), list) + '</p>' : '') +
      (val('foot') ? '<p class="mt-pv-fine">' + marked(val('foot'), list) + '</p>' : '') + '</div>';
  }
  function insert(field) {
    var el = last && document.body.contains(last) ? last : $('mt-body');
    var s = el.selectionStart == null ? el.value.length : el.selectionStart, e = el.selectionEnd == null ? s : el.selectionEnd;
    var w = '{' + field + '}';
    el.value = el.value.slice(0, s) + w + el.value.slice(e);
    el.focus();
    el.setSelectionRange(s + w.length, s + w.length);
    el.dispatchEvent(new Event('input', { bubbles: true }));
  }
  function edMsg(t, tone) { $('mtEdMsg').textContent = t || ''; $('mtEdMsg').className = 'msg' + (tone ? ' ' + tone : ''); }

  function save() {
    var it = st.ed, go = $('mtEdSave');
    var v = { name: val('name'), subject: val('subject'), subject2: val('subject2'), body: val('body'), button: val('button'), legal: val('legal'),
      disclaimer: val('disclaimer'), foot: val('foot'), to: val('to'), on: $('mtOn') ? $('mtOn').getAttribute('aria-checked') === 'true' : true };
    var bad = odd(texts(), fieldsOf(it.kind));
    var refuse = it.named && (v.name.length < 2 || v.name.length > 80) ? ['name', SAID['bad-name']]
      : it.to && !window.ADspaceWords.emailOk(v.to) ? ['to', SAID['bad-email']]
      : v.subject.length < 2 ? ['subject', SAID['bad-subject']]
      : it.two && v.subject2.length < 2 ? ['subject2', SAID['bad-subject']]
      : v.body.length < 2 ? ['body', SAID['bad-body']]
      : it.btn && (v.button.length < 2 || v.button.length > 40) ? ['button', SAID['bad-button']]
      : it.kind === 'invoice' && !/\{\s*invoices\s*\}/i.test(v.body) ? ['body', SAID['no-invoices']]
      : it.kind === 'code' && /\{\s*code\s*\}/i.test(v.subject) ? ['subject', SAID['code-in-subject']]
      : it.kind === 'code' && !/\{\s*code\s*\}/i.test(v.body) ? ['body', SAID['no-code']]
      : bad.length ? ['body', L().unknownField(bad[0], fieldsOf(it.kind))] : null;
    if (refuse) { edMsg(refuse[1], 'err'); var f = $('mt-' + refuse[0]); if (f) f.focus(); return; }
    go.disabled = true;
    var p = it.isNew
      ? saveWith('email_template_save', { p_id: null, p_audience: it.rec === 'suppliers' ? 'supplier' : 'client', p_name: v.name, p_subject: v.subject, p_body: v.body })
      : it.save(v);
    p.then(function (err) {
      go.disabled = false;
      if (err) { edMsg(err, 'err'); return; }
      window.ADspaceSheet.clean();
      var keep = it.isNew ? '' : it.id;
      load().then(function () {
        showList(keep);
        msg('Saved.', 'ok');
        if (st.say) st.say('Saved.', 'ok');
      }).catch(function () { showList(keep); msg('Saved.', 'ok'); });
    });
  }

  function del(it) {
    shutMenus();
    window.ADspaceConfirm.ask({ title: 'Delete this template?', body: '“' + it.name + '” will no longer be offered. Emails already sent are not changed. This cannot be undone.',
      go: 'Delete', tone: 'danger', wait: true }, function () {
      return rpc('email_template_delete', { p_id: it.tid }).then(function (d) {
        if (d && d.error) return said(d);
        return load().then(function () { paint(); msg('Deleted.', 'ok'); return ''; });
      }).catch(function (e) { return (e && e.message) || 'Not deleted. The database refused the request.'; });
    });
  }

  function wire() {
    if (st.wired || !$('mtSheet')) return;
    st.wired = true;
    $('mtClose').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('mtDone').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('mtList').addEventListener('click', function (e) {
      var b = e.target.closest('[data-a]');
      if (!b) return;
      var a = b.getAttribute('data-a'), row = b.closest('.mt-row');
      var it = row && st.items.filter(function (i) { return i.id === row.getAttribute('data-id'); })[0];
      if (a === 'add') { msg(''); edit(null, b); return; }
      if (!it) return;
      if (a === 'edit') { msg(''); edit(it, b); }
      else if (a === 'menu') {
        e.stopPropagation();
        var mn = b.parentNode.querySelector('[data-menu]'), was = mn.hidden;
        shutMenus();
        mn.hidden = !was; b.setAttribute('aria-expanded', String(was));
        if (was) window.ADspaceMenu.place(b, mn);
      } else if (a === 'delete') del(it);
    });
    document.addEventListener('click', function (e) { if (!e.target.closest || !e.target.closest('#mtList .team-act')) shutMenus(); });
    var form = $('mtEdForm');
    form.addEventListener('focusin', function (e) { if (/^(TEXTAREA|INPUT)$/.test(e.target.tagName) && e.target.id !== 'mt-to' && e.target.id !== 'mt-name') last = e.target; });
    form.addEventListener('input', function () { if (st.ed) preview(); });
    form.addEventListener('mousedown', function (e) { if (e.target.closest('.mt-chip')) e.preventDefault(); });
    form.addEventListener('click', function (e) {
      var c = e.target.closest('.mt-chip');
      if (c) { insert(c.getAttribute('data-f')); return; }
      var sw = e.target.closest('#mtOn');
      if (sw) sw.setAttribute('aria-checked', sw.getAttribute('aria-checked') === 'true' ? 'false' : 'true');
    });
    $('mtEdSave').addEventListener('click', save);
    function back() { var id = st.ed && !st.ed.isNew ? st.ed.id : ''; st.ed = null; showList(id); }
    $('mtEdCancel').addEventListener('click', back);
    $('mtEdClose').addEventListener('click', back);
  }

  /* A section's ⋯ item (`data-mailtpl="{rec}"`): drawn for a reader who
     may open that recipient's templates (`ADspaceAdmin`'s access pass asks
     `may`), opened at its press. */
  document.addEventListener('click', function (e) {
    var b = e.target.closest && e.target.closest('[data-mailtpl]');
    if (b && !b.closest('#mtSheet, #mtEdSheet')) open(b, null, b.getAttribute('data-mailtpl'));
  });

  window.ADspaceMailTpl = { open: open, may: mayRec, _odd: odd };
})();
