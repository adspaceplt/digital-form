/* A supplier's details form (2026-10-18; the user: the Jotform supplier
 * sign-up "could jump into the fill in via portal and data sync into it
 * similar as client billing section"; "invite only, with create link and set
 * the supplier id before sending"; "nric only for individuals").
 *
 * `/supplier/?k={key}`, a link the team makes on a supplier in
 * Documents, Suppliers (`supplier_link`). The page reads only the name and
 * Supplier ID the link is for and when it ends (`supplier_form_read`), never
 * a value the record holds, and sends the answers once
 * (`supplier_form_submit`), checked as the Jotform form checked them; they
 * wait on the supplier for the team to take in. English, as the form was.
 *
 * An update link (2026-10-20), sent to a supplier already approved, opens
 * on the details held but the NRIC and the bank details, which it never
 * reads: left blank, they keep what is held. */
(function () {
  var API = window.ADspaceAPI, db = API && API.client;
  var $ = function (id) { return document.getElementById(id); };
  var esc = window.ADspaceWords.esc;
  var W = window.ADspaceWords.of({ en: {} }).en;

  /* What supplier_values_check accepts, in its order. */
  var BANKS = ['Maybank', 'CIMB', 'Hong Leong Bank', 'RHB', 'BSN', 'UOB', 'OCBC', 'AmBank', 'Bank Islam', 'Public Bank',
    'Alliance Bank', 'Standard Chartered Bank', 'Touch N Go Digital', '[SG] DBS/POSB', '[SG] OCBC', '[SG] UOB', '[SG] CIMB',
    '[SG] Maybank', '[SG] Bank of China'];
  /* A Malaysian or Singapore number, as supplier_number_ok reads it. */
  function numberOk(t, mobile) {
    var d = String(t || '').replace(/\D/g, ''), sg = null, my = null;
    if (d.length === 8) sg = d;
    else if (d.length === 10 && /^65/.test(d)) sg = d.slice(2);
    else if (/^0/.test(d)) my = d;
    else if (/^60/.test(d)) my = '0' + d.slice(2);
    if (sg) return (mobile ? /^[89]\d{7}$/ : /^[689]\d{7}$/).test(sg);
    if (!my) return false;
    return /^01\d{8,9}$/.test(my) || (!mobile && /^0[3-9]\d{7,8}$/.test(my));
  }
  var TERMS = ['NET 7', 'NET 14', 'NET 30', 'NET 45', 'NET 60'];
  /* The authorisation the Jotform form carried, word for word. */
  var AUTH = [
    'I / We hereby authorise ADSPACE PLT to credit all payments due to me / us to the account above.',
    'Any amount so credited shall constitute a valid discharge of ADSPACE PLT’s obligations to me / us.',
    'This authorisation shall remain in force until I / we revoke it by written notice to ADSPACE PLT.',
    'I / We shall notify ADSPACE PLT in writing at least 30 days before any change to my / our particulars, and such notice takes effect upon ADSPACE PLT’s written acknowledgement of its receipt.',
    'ADSPACE PLT may, at its absolute discretion, terminate this arrangement by written notice to my / our last known address or email.',
    'I / We hereby declare that all the information provided above is true and correct.'
  ];
  var MARK = '<span class="qs-mark" aria-hidden="true"><svg viewBox="0 0 16 16" width="12" height="12"><path d="M3.5 8.4l2.9 2.9 6.1-6.6" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg></span>';

  var key = (new URLSearchParams(location.search).get('k') || '').trim().toLowerCase();
  var info = null, state = 'loading', typed = { kind: 'company', currency: 'MYR' }, consent = false, sending = false;
  /* An update link: the bank details and the NRIC held are kept when left blank. */
  var update = false, bankHeld = false, nricHeld = false;
  function bankKept() { return update && bankHeld && !String(typed.bank_account || '').trim(); }
  var root = function () { return $('sfRoot'); };

  function day(iso) { return window.ADspaceClock.date(iso, { long: true }); }
  function cover(title, text) {
    root().innerHTML = '<section class="cover" data-shown><div class="cover-inner"><div class="cover-panel"><h2>' + esc(title) + '</h2><p>' + esc(text) + '</p></div></div></section>';
  }
  function field(id, label, html, hint) {
    return '<div class="field" id="' + id + 'Wrap"><label class="field-label" for="' + id + '">' + esc(label) + '</label>' + html +
      (hint ? '<span class="qs-hint">' + esc(hint) + '</span>' : '') + '<span class="msg" id="' + id + 'Msg"></span></div>';
  }
  function input(id, k, req, attrs) {
    return '<input class="input" id="' + id + '" data-k="' + k + '"' + (req ? ' aria-required="true"' : '') + ' ' + (attrs || '') +
      ' value="' + esc(typed[k] || '') + '">';
  }
  function select(id, k, req, opts, none) {
    return '<select class="select" id="' + id + '" data-k="' + k + '"' + (req ? ' aria-required="true"' : '') + '>' +
      (none ? '<option value="">' + esc(none) + '</option>' : '') +
      opts.map(function (o) { return '<option value="' + esc(o) + '"' + (typed[k] === o ? ' selected' : '') + '>' + esc(o) + '</option>'; }).join('') +
      '</select>';
  }
  function seg(id, k, opts, label) {
    return '<select class="select" id="' + id + '" data-k="' + k + '" data-seg aria-label="' + esc(label) + '">' +
      opts.map(function (o) { return '<option value="' + o[0] + '"' + (typed[k] === o[0] ? ' selected' : '') + '>' + esc(o[1]) + '</option>'; }).join('') + '</select>';
  }
  function paintForm() {
    var ind = typed.kind === 'individual', keepBank = update && bankHeld, keepNric = update && nricHeld;
    return '<div class="qs-step" data-shown><h1 class="qs-title">' + (update ? 'Update Supplier Details' : 'Supplier Details') + '</h1>' +
      /* Who asks, then whose details (2026-10-20, SPF-3). */
      '<p class="qs-lead">For ADspace · ' + (info.name ? esc(info.name) + ' · ' : '') + 'Supplier ID ' + esc(info.code) + '</p>' +
      '<form class="qs-form" id="sfForm" novalidate>' +
      '<section class="qs-sec"><h2 class="qs-sec-h">Billing details</h2>' +
        field('sfKind', 'Registered as', seg('sfKind', 'kind', [['company', 'Company'], ['individual', 'Individual']], 'Registered as')) +
        field('sfName', ind ? 'Personal name' : 'Company name', '<textarea class="input" id="sfName" data-k="name" data-oneline aria-required="true" rows="1" maxlength="160" autocomplete="organization" placeholder="' + (ind ? 'John Doe' : 'COMPANY NAME SDN BHD') + '">' + esc(typed.name || '') + '</textarea>') +
        field('sfBrn', '12-digit SSM BRN', input('sfBrn', 'brn', !ind, 'maxlength="14" inputmode="numeric" placeholder="' + (ind ? 'Optional' : '12 digits') + '"')) +
        (ind ? field('sfNric', 'NRIC', input('sfNric', 'nric', !keepNric, 'maxlength="14" inputmode="numeric" placeholder="' + (keepNric ? 'Leave blank to keep the NRIC on file' : 'XXXXXX-XX-XXXX') + '"')) : '') +
        field('sfTin', 'TIN', input('sfTin', 'tin', true, 'maxlength="20" autocapitalize="characters" placeholder="Letters and digits"')) +
        field('sfSst', 'SST registration no.', input('sfSst', 'sst_no', false, 'maxlength="17" autocapitalize="characters" placeholder="Optional"')) +
        field('sfPhone', 'Office / mobile', input('sfPhone', 'phone', true, 'type="tel" inputmode="tel" autocomplete="tel" placeholder="07-123 4567"')) +
        field('sfAddr', 'Billing address', '<textarea class="input" id="sfAddr" data-k="address" aria-required="true" rows="3" maxlength="400" autocomplete="street-address">' + esc(typed.address || '') + '</textarea>') +
      '</section>' +
      '<section class="qs-sec"><h2 class="qs-sec-h">Person in charge</h2>' +
        field('sfContact', 'Legal name', input('sfContact', 'contact_name', true, 'maxlength="80" autocomplete="name" placeholder="John Doe"')) +
        field('sfRole', 'Designation', input('sfRole', 'designation', true, 'maxlength="80" autocomplete="organization-title"')) +
        field('sfEmail', 'Email', input('sfEmail', 'email', true, 'type="email" maxlength="160" autocomplete="email" placeholder="email@adspace.me"')) +
        field('sfMobile', 'Mobile / WhatsApp', input('sfMobile', 'mobile', true, 'type="tel" inputmode="tel" placeholder="012-345 6789"')) +
      '</section>' +
      '<section class="qs-sec"><h2 class="qs-sec-h">Payment details</h2>' +
        (keepBank ? '<p class="qs-note">Leave the account number blank to keep the current bank details. A new bank account must be approved by ADspace before any payment is made to it.</p>' : '') +
        field('sfTerm', 'Payment term', select('sfTerm', 'payment_term', true, TERMS, 'Choose a term'), 'Subject to approval.') +
        field('sfCur', 'Currency', seg('sfCur', 'currency', [['MYR', 'MYR / RM'], ['SGD', 'SGD / S$']], 'Currency')) +
        field('sfPayee', 'Payee name', input('sfPayee', 'payee_name', !keepBank, 'maxlength="120"'), 'As shown on the bank account.') +
        field('sfBank', 'Bank', select('sfBank', 'bank_name', !keepBank, BANKS, keepBank ? 'Keep current bank' : 'Choose a bank')) +
        field('sfAcct', 'Account number', input('sfAcct', 'bank_account', !keepBank, 'maxlength="24" inputmode="numeric"' + (keepBank ? ' placeholder="Leave blank to keep current"' : ''))) +
        field('sfFin', 'Finance email', input('sfFin', 'finance_email', true, 'type="email" maxlength="160" placeholder="email@adspace.me"')) +
        field('sfSwift', 'SWIFT code', input('sfSwift', 'swift', false, 'maxlength="11" autocapitalize="characters" placeholder="Optional"')) +
        field('sfBankAddr', 'Bank address', '<textarea class="input" id="sfBankAddr" data-k="bank_address" rows="2" maxlength="300" placeholder="Optional">' + esc(typed.bank_address || '') + '</textarea>') +
      '</section>' +
      '<ol class="qs-notes sf-auth">' + AUTH.map(function (x) { return '<li>' + esc(x) + '</li>'; }).join('') + '</ol>' +
      '<label class="qs-consent"><input type="checkbox" id="sfConsent"' + (consent ? ' checked' : '') + '>' + MARK + '<span class="qs-text">I agree to the authorisation above.</span></label>' +
      '<span class="msg" id="sfConsentMsg"></span>' +
      '<p class="qs-note">This form is open until ' + esc(day(info.expires_at)) + '.</p>' +
      '<p class="msg" id="sfMsg" role="status"></p>' +
      '</form></div>' +
      '<div class="qs-foot"><button class="btn btn-primary" type="button" id="sfSubmit">Submit</button></div>';
  }
  function paintDone() {
    root().innerHTML = '<div class="qs-step qs-done" data-shown><span class="qs-tick" aria-hidden="true">' +
      '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12 5 5 9-10"/></svg></span>' +
      '<h1 class="qs-title">Details received</h1><p>' + (update ? 'Thank you. ADspace will review the changes.' : 'Thank you. ADspace will review your details.') + '</p></div>';
  }
  function paint() {
    if (state === 'loading') return;
    /* A supplier has no account manager (CP-11). */
    if (state === 'bad') { cover(W.notFound, W.contactAdspace); return; }
    if (state === 'fail') { cover(W.failTitle, W.failTextAdspace); return; }
    if (state === 'expired') { cover('Link expired', W.contactAdspace); return; }
    if (state === 'submitted') { cover('Details received', 'This form has already been submitted.'); return; }
    if (state === 'done') { paintDone(); return; }
    root().innerHTML = paintForm();
    if (window.ADspaceForm && window.ADspaceForm.scan) window.ADspaceForm.scan(root());
    Array.prototype.forEach.call(root().querySelectorAll('select[data-seg]'), function (s) {
      s.addEventListener('change', function () { read(); if (s.id === 'sfKind') paint(); });
    });
  }
  function read() {
    Array.prototype.forEach.call(root().querySelectorAll('[data-k]'), function (el) { typed[el.getAttribute('data-k')] = el.value; });
    consent = Boolean($('sfConsent') && $('sfConsent').checked);
  }
  function say(id, text, tone) {
    var m = $(id); if (!m) return;
    m.textContent = text || ''; m.className = 'msg' + (text ? ' ' + (tone || 'err') : '');
  }
  var ID = { kind: 'sfKind', name: 'sfName', brn: 'sfBrn', nric: 'sfNric', tin: 'sfTin', sst_no: 'sfSst', phone: 'sfPhone',
    address: 'sfAddr', contact_name: 'sfContact', designation: 'sfRole', email: 'sfEmail', mobile: 'sfMobile',
    payment_term: 'sfTerm', currency: 'sfCur', payee_name: 'sfPayee', bank_name: 'sfBank', bank_account: 'sfAcct',
    finance_email: 'sfFin', swift: 'sfSwift', bank_address: 'sfBankAddr' };
  /* Each field's own fault, as supplier_values_check refuses it. */
  var FAULT = {
    name: 'Enter a name of 2 to 160 characters.', brn: 'Enter the 12-digit BRN, digits only.',
    nric: 'Enter the NRIC as XXXXXX-XX-XXXX.', tin: 'Enter the TIN, 5 to 20 letters or digits.',
    sst_no: 'Enter the SST no. as AXX-XXXX-XXXXXXXX.', phone: 'Enter a Malaysian or Singapore number, for example 07-123 4567.',
    mobile: 'Enter a Malaysian or Singapore mobile number, for example 012-345 6789.', address: 'Enter the full billing address.',
    contact_name: 'Enter the legal name.', designation: 'Enter the designation.', email: 'Enter a valid email address.',
    finance_email: 'Enter a valid email address.', payment_term: 'Choose a payment term.', payee_name: 'Enter the payee name.',
    bank_name: 'Choose a bank.', bank_account: 'Enter the account number, digits only.',
    swift: 'Enter the SWIFT code, 8 or 11 letters or digits.', bank_address: 'The bank address may contain up to 300 characters.',
    kind: 'Choose how you are registered.', currency: 'Choose a currency.'
  };
  function check() {
    var first = null, mail = { test: ADspaceWords.emailOk }, ind = typed.kind === 'individual';
    var v = function (k) { return String(typed[k] || '').trim(); };
    var digits = function (k) { return v(k).replace(/\D/g, ''); };
    var bad = function (k) {
      var id = ID[k]; say(id + 'Msg', FAULT[k]);
      if ($(id)) $(id).setAttribute('aria-invalid', 'true');
      if (!first) first = id;
    };
    Object.keys(ID).forEach(function (k) { say(ID[k] + 'Msg', ''); if ($(ID[k])) $(ID[k]).removeAttribute('aria-invalid'); });
    say('sfConsentMsg', '');
    if (v('name').length < 2) bad('name');
    if ((!ind || digits('brn')) && !/^\d{12}$/.test(digits('brn'))) bad('brn');
    if (ind && !(update && nricHeld && !digits('nric')) && !/^\d{12}$/.test(digits('nric'))) bad('nric');
    if (!/^[A-Za-z0-9]{5,20}$/.test(v('tin').replace(/\s+/g, ''))) bad('tin');
    if (v('sst_no') && !/^[A-Za-z]\d{2}-\d{4}-\d{8}$/.test(v('sst_no').replace(/\s+/g, ''))) bad('sst_no');
    if (!numberOk(v('phone'), false)) bad('phone');
    if (v('address').length < 10) bad('address');
    if (v('contact_name').length < 2) bad('contact_name');
    if (v('designation').length < 2) bad('designation');
    if (!mail.test(v('email'))) bad('email');
    if (!numberOk(v('mobile'), true)) bad('mobile');
    if (TERMS.indexOf(v('payment_term')) < 0) bad('payment_term');
    if (!bankKept()) {
      if (v('payee_name').length < 2) bad('payee_name');
      if (BANKS.indexOf(v('bank_name')) < 0) bad('bank_name');
      if (!/^\d{6,20}$/.test(v('bank_account').replace(/[\s-]/g, ''))) bad('bank_account');
    }
    if (!mail.test(v('finance_email'))) bad('finance_email');
    if (!bankKept() && v('swift') && !/^[A-Za-z]{6}[A-Za-z0-9]{2}([A-Za-z0-9]{3})?$/.test(v('swift').replace(/\s+/g, ''))) bad('swift');
    if (!consent) { say('sfConsentMsg', 'Tick to agree.'); if (!first) first = 'sfConsent'; }
    if (first && $(first)) $(first).focus();
    return !first;
  }
  function submit(btn) {
    if (sending) return;
    read();
    if (!check()) return;
    sending = true; btn.disabled = true;
    var answers = { authorise: 'true' };
    Object.keys(ID).forEach(function (k) { answers[k] = String(typed[k] || '').trim(); });
    if (typed.kind !== 'individual') answers.nric = '';
    db.rpc('supplier_form_submit', { p_key: key, p_answers: answers }).then(function (r) {
      var d = r.data || {};
      if (r.error) throw r.error;
      if (d.error === 'submitted') { state = 'submitted'; paint(); return; }
      if (d.error === 'expired') { state = 'expired'; paint(); return; }
      if (d.error === 'not_found') { state = 'bad'; paint(); return; }
      var k = d.error && d.error.indexOf('bad-') === 0 ? d.error.slice(4) : null;
      if (k && ID[k]) {
        say(ID[k] + 'Msg', FAULT[k]);
        if ($(ID[k])) { $(ID[k]).setAttribute('aria-invalid', 'true'); $(ID[k]).focus(); }
        return;
      }
      if (d.error) throw new Error(d.error);
      state = 'done'; paint(); window.scrollTo(0, 0);
    }).catch(function () {
      say('sfMsg', W.notSentAdspace);
    }).then(function () { sending = false; if (btn && btn.isConnected) btn.disabled = false; });
  }

  document.addEventListener('click', function (e) {
    var b = e.target.closest('#sfSubmit');
    if (b) submit(b);
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && e.target && e.target.matches && e.target.matches('#sfForm input:not([type=checkbox]), #sfForm textarea[data-oneline]') && !e.isComposing) {
      /* Enter moves to the next field; only the last one submits
         (2026-10-20, SPF-2). */
      e.preventDefault();
      var all = Array.prototype.filter.call($('sfForm').querySelectorAll('input, select, textarea'), function (f) {
        return !f.disabled && f.offsetParent !== null && f.type !== 'hidden';
      });
      var at = all.indexOf(e.target), next = all[at + 1];
      if (next) { next.focus(); return; }
      if ($('sfSubmit')) submit($('sfSubmit'));
    }
  });

  if (!db) { state = 'fail'; paint(); return; }
  if (!/^[a-z0-9]{8}$/.test(key)) { state = 'bad'; paint(); return; }
  db.rpc('supplier_form_read', { p_key: key }).then(function (r) {
    var d = r.data || {};
    if (r.error) throw r.error;
    if (d.error === 'expired') state = 'expired';
    else if (d.error === 'submitted') state = 'submitted';
    else if (d.error || !d.ok) state = 'bad';
    else {
      info = d; state = 'open'; typed.name = d.name || '';
      if (d.purpose === 'update') {
        update = true; bankHeld = Boolean(d.bank_held); nricHeld = Boolean(d.nric_held);
        Object.keys(d.current || {}).forEach(function (k) { typed[k] = d.current[k]; });
      }
    }
    paint();
  }).catch(function () { state = 'fail'; paint(); });
})();
