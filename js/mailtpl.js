/* Email templates (2026-11-10; the overnight Settings review): every email
 * wording the portal sends, one sheet listing them by recipient (Clients,
 * Suppliers, Creators) and one editor for all of them.
 *
 *   ADspaceMailTpl.open(btn, say)   Settings, Messages: Email templates
 *   ADspaceMailTpl.line()           what its Settings row reads
 *
 * The words stay where each sender reads them (supplier_email_templates,
 * client_email_templates, email_templates, the two invoice tables,
 * creator_email_templates): each template saves through its own function,
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

  var NOT_YET = 'This feature is not available yet. Please contact an admin.';
  var SAID = {
    denied: 'You do not have permission to change these templates. Please ask an admin.',
    'bad-subject': 'Enter a subject of 2 to 200 characters.',
    'bad-body': 'Enter a message of 2 to 5,000 characters.',
    'bad-name': 'Enter a template name of 2 to 80 characters.',
    taken: 'A template of this name already exists. Choose another name.',
    'bad-email': 'Enter a valid email address for the finance team.',
    'no-invoices': 'The message must keep {invoices}, where the table of invoices goes.',
    'too-long': 'Keep the legal note and the disclaimer to 1,000 characters each.',
    'not-found': 'This template no longer exists.'
  };
  var REC = [['clients', 'Clients'], ['suppliers', 'Suppliers'], ['creators', 'Creators']];
  var CM_WORD = { received: 'Details received', review: 'Details to review', approved: 'Details approved',
    request: 'Payment request', posted: 'Post recorded', paid: 'Payment sent' };

  function may(key) { var A = window.ADspaceAdmin; return Boolean(A && A.may && A.may(key, 'work')); }
  function full(sec) { var A = window.ADspaceAdmin; return Boolean(A && A.may && A.may(sec, 'manage')); }
  function biz() { return may('team.settings'); }

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

  /* Every template the reader may change, each with how it is edited and
     saved. */
  function load() {
    var ins = window.ADspaceInvoices;
    return Promise.all([
      soft(rpc('template_fields_all')),
      biz() ? soft(rpc('client_email_templates_list')) : null,
      biz() && ins ? soft(rpc('invoice_email_template_get')) : null,
      biz() && ins ? soft(rpc('invoice_send_template_get')) : null,
      biz() ? soft(rpc('email_templates_list')) : null,
      full('suppliers') ? soft(rpc('supplier_email_templates_list')) : null,
      biz() ? soft(rpc('creator_email_templates_get')) : null
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
      ((a[4] && a[4].rows) || []).forEach(function (t) {
        out.push(free(t));
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
  function recs() {
    return REC.filter(function (r) {
      return st.items.some(function (i) { return i.rec === r[0]; }) || (st.free && r[0] !== 'creators');
    });
  }
  function msg(text, tone) { var m = $('mtMsg'); if (m) { m.textContent = text || ''; m.className = 'msg' + (tone ? ' ' + tone : ''); } }
  var PEN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 20h4L19 9l-4-4L4 16v4Z"/></svg>';
  var PLUS = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>';
  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>';

  function paint() {
    var box = $('mtList'), seg = $('mtRec');
    var list = recs();
    if (!list.some(function (r) { return r[0] === st.rec; })) st.rec = list[0] ? list[0][0] : 'clients';
    var want = list.map(function (r) { return r[0]; }).join(',');
    if (seg.getAttribute('data-has') !== want) {
      seg.innerHTML = list.map(function (r) { return '<option value="' + r[0] + '">' + r[1] + '</option>'; }).join('');
      seg.setAttribute('data-has', want);
    }
    seg.value = st.rec;
    $('mtRecRow').hidden = list.length < 2;
    var mine = st.items.filter(function (i) { return i.rec === st.rec; });
    var secs = [];
    mine.forEach(function (i) { if (secs.indexOf(i.sec) < 0) secs.push(i.sec); });
    if (st.free && st.rec !== 'creators' && secs.indexOf('New email') < 0) secs.push('New email');
    if (!secs.length) { box.innerHTML = '<p class="emptyline">No templates.</p>'; return; }
    box.innerHTML = secs.map(function (s) {
      var rows = mine.filter(function (i) { return i.sec === s; });
      var add = s === 'New email' && st.free;
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
        '<button class="btn btn-sm" type="button" data-a="edit" aria-label="Edit ' + esc(i.name) + '">' + PEN + 'Edit</button></div></div>';
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
  function open(btn, say) {
    wire();
    st.opener = btn || null; st.say = say || null;
    msg('');
    window.ADspaceSheet.show($('mtSheet'), { opener: st.opener });
    var box = $('mtList');
    if (window.ADspaceState && window.ADspaceState.skeleton) window.ADspaceState.skeleton(box, 3);
    load().then(paint).catch(function (e) {
      if (window.ADspaceState && window.ADspaceState.failLine) window.ADspaceState.failLine(box, 'The templates', (e && e.message) || 'Could not load.', function () { open(btn, say); });
    });
  }

  /* ---- The editor -------------------------------------------------------- */
  var KIND_FIELDS = { client: 'client', invoice: 'invoice', free: 'free', supplier: 'supplier', 'creator-details': 'creator-details', 'creator-booking': 'creator-booking' };
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
    h += '<div class="mt-chips" role="group" aria-label="Insert a field">' + f.map(function (x) {
      return '<button class="btn btn-sm mt-chip" type="button" data-f="' + esc(x) + '">{' + esc(x) + '}</button>';
    }).join('') + '</div><p class="msg warn mt-odd" id="mtOdd" role="status" hidden></p>';
    if (it.kind === 'invoice') h += box('legal', 'Legal note', it.legal, 'area3') + box('disclaimer', 'Disclaimer', it.disclaimer, 'area3');
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
  function texts() { return ['subject', 'subject2', 'body', 'legal', 'disclaimer'].map(val).join('\n'); }
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
    ['subject', 'subject2', 'body', 'legal', 'disclaimer'].forEach(function (n) {
      var el = $('mt-' + n);
      if (el) el.setAttribute('aria-invalid', String(odd(el.value, list).length > 0));
    });
    var paras = val('body').split(/\n{2,}/).filter(Boolean);
    $('mtPreview').innerHTML = '<div class="inv-mail-card">' +
      '<p class="mt-pv-subj">' + (val('subject') ? marked(val('subject'), list) : '<span class="mt-pv-none">No subject</span>') + '</p>' +
      (paras.length ? paras.map(function (p) { return '<p>' + marked(p, list).replace(/\n/g, '<br>') + '</p>'; }).join('') : '<p class="mt-pv-none">No message</p>') +
      (val('legal') ? '<p class="mt-pv-fine">' + marked(val('legal'), list) + '</p>' : '') +
      (val('disclaimer') ? '<p class="mt-pv-fine">' + marked(val('disclaimer'), list) + '</p>' : '') + '</div>';
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
    var v = { name: val('name'), subject: val('subject'), subject2: val('subject2'), body: val('body'), legal: val('legal'),
      disclaimer: val('disclaimer'), to: val('to'), on: $('mtOn') ? $('mtOn').getAttribute('aria-checked') === 'true' : true };
    var bad = odd(texts(), fieldsOf(it.kind));
    var refuse = it.named && (v.name.length < 2 || v.name.length > 80) ? ['name', SAID['bad-name']]
      : it.to && !window.ADspaceWords.emailOk(v.to) ? ['to', SAID['bad-email']]
      : v.subject.length < 2 ? ['subject', SAID['bad-subject']]
      : it.two && v.subject2.length < 2 ? ['subject2', SAID['bad-subject']]
      : v.body.length < 2 ? ['body', SAID['bad-body']]
      : it.kind === 'invoice' && !/\{\s*invoices\s*\}/i.test(v.body) ? ['body', SAID['no-invoices']]
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
    window.ADspaceConfirm.ask({ title: 'Delete this template?', body: '“' + it.name + '” will no longer be offered. Emails already sent keep their words. This cannot be undone.',
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
    $('mtRec').addEventListener('change', function () { st.rec = this.value; msg(''); paint(); });
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

  /* The Settings row: how many each recipient holds. */
  function line() {
    return load().then(function (items) {
      return recs().map(function (r) {
        var n = items.filter(function (i) { return i.rec === r[0]; }).length;
        return r[1] + ' ' + n;
      }).join(' · ');
    });
  }

  window.ADspaceMailTpl = { open: open, line: line, _odd: odd };
})();
