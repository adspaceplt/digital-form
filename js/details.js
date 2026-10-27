/* The client's details form (2026-10-14; the user: "a form … for client to
 * fill in (public link, no need any login when sent … company name BRN, old
 * BRN, TIN, contact hp, address, email etc. like a full set").
 *
 * `/details/?k={key}`, a link the team makes on a client's Billing pane
 * (`client_details_link`). The page reads only the brand the link is for and
 * when it ends (`client_details_read`), never a value the record holds, and
 * sends the answers once (`client_details_submit`); they wait on the client's
 * Billing for the team to take into the record. English and 中文. */
(function () {
  var API = window.ADspaceAPI, db = API && API.client;
  var $ = function (id) { return document.getElementById(id); };
  var esc = window.ADspaceWords.esc;
  var LANG_KEY = 'adspace.details.lang';
  var lang = 'en';
  try { if (localStorage.getItem(LANG_KEY) === 'zh') lang = 'zh'; } catch (e) {}

  var WORDS = window.ADspaceWords.of({
    en: {
      lang: '中文', title: 'Company Details', for: 'For {b}',
      company: 'Company', legal: 'Registered company name', brn: 'Business registration no.',
      brnHint: 'The new 12-digit number.', old: 'Old registration no.', tin: 'TIN',
      sst: 'SST registration no.', address: 'Billing address', finance: 'Finance email',
      contact: 'Billing contact', sal: 'Salutation', name: 'Name', phone: 'Mobile number', email: 'Email',
      optional: 'Optional', consent: 'I confirm these details are correct, and consent to ADspace keeping them for business purposes.',
      submit: 'Submit', ends: 'This form is open until {d}.',
      req: 'This is required.', badBrn: 'Enter the registration number as shown on the company\'s registration.',
      badEmail: 'Enter a valid email address.', badPhone: 'Enter a mobile number of 8 to 15 digits.',
      badAddr: 'Enter the full billing address.', badCode: 'Enter {a} to {b} letters or digits, as registered.', tick: 'Tick to confirm.',
      doneT: 'Details received', doneP: 'Thank you. Your ADspace account manager will review them.',
      expT: 'Link expired', submittedT: 'Details received', submittedP: 'This form has already been submitted.'
    },
    zh: {
      lang: 'EN', title: '公司资料', for: '{b}',
      company: '公司', legal: '公司注册名称', brn: '公司注册号码',
      brnHint: '新的12位号码。', old: '旧注册号码', tin: '税务识别号（TIN）',
      sst: 'SST 注册号码', address: '账单地址', finance: '财务邮箱',
      contact: '账单联系人', sal: '称谓', name: '姓名', phone: '手机号码', email: '邮箱',
      optional: '选填', consent: '我确认以上资料无误，并同意 ADspace 保存这些资料用于业务用途。',
      submit: '提交', ends: '此表格开放至 {d}。',
      req: '此项为必填。', badBrn: '请按公司注册文件填写注册号码。',
      badEmail: '请输入有效的邮箱地址。', badPhone: '请输入8至15位数字的手机号码。',
      badAddr: '请填写完整的账单地址。', badCode: '请按注册资料填写{a}至{b}位字母或数字。', tick: '请勾选确认。',
      doneT: '资料已收到', doneP: '谢谢。您的 ADspace 客户经理将审阅这些资料。',
      expT: '链接已过期', submittedT: '资料已收到', submittedP: '此表格已提交。'
    }
  });
  var t = function () { return WORDS[lang]; };
  var f = function (s, v) { return String(s).replace(/\{(\w+)\}/g, function (m, k) { return v[k] == null ? m : v[k]; }); };

  /* The contact sheet's salutations, which client_details_submit accepts. */
  var SALUTATIONS = ['Mr', 'Ms', 'Mrs', 'Mdm', 'Dr', 'Prof', "Dato'", 'Datin', 'Datuk', "Dato' Sri", 'Datin Sri',
    'Tan Sri', 'Puan Sri', 'Tun', 'Tuan', 'Puan', 'Encik', 'Cik'];
  var SAL_ZH = { Mr: '先生', Ms: '女士', Mrs: '太太', Mdm: '夫人', Dr: '博士', Prof: '教授' };
  var FIELDS = ['legal_name', 'company_no', 'company_no_old', 'tin', 'sst_no', 'billing_address', 'finance_email',
    'contact_salutation', 'contact_name', 'contact_phone', 'contact_email'];
  var MARK = '<span class="qs-mark" aria-hidden="true"><svg viewBox="0 0 16 16" width="12" height="12"><path d="M3.5 8.4l2.9 2.9 6.1-6.6" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg></span>';

  var key = (new URLSearchParams(location.search).get('k') || '').trim().toLowerCase();
  var info = null, state = 'loading', typed = {}, consent = false, sending = false;
  var root = function () { return $('dfRoot'); };

  function day(iso) {
    var C = window.ADspaceClock;
    if (C && C.date) return C.date(iso, { zh: lang === 'zh', long: true });
    return new Date(iso).toLocaleDateString(lang === 'zh' ? 'zh-CN' : 'en-GB', { timeZone: 'Asia/Kuala_Lumpur', day: 'numeric', month: 'long', year: 'numeric' });
  }
  function cover(title, text) {
    root().innerHTML = '<section class="cover" data-shown><div class="cover-inner"><div class="cover-panel"><h2>' + esc(title) + '</h2><p>' + esc(text) + '</p></div></div></section>';
  }
  function field(id, label, req, html, hint) {
    return '<div class="field"><label class="field-label" for="' + id + '">' + esc(label) + '</label>' + html +
      (hint ? '<span class="qs-hint">' + esc(hint) + '</span>' : '') + '<span class="msg" id="' + id + 'Msg"></span></div>';
  }
  function input(id, k, req, attrs) {
    return '<input class="input" id="' + id + '" data-k="' + k + '"' + (req ? ' aria-required="true"' : '') + ' ' + (attrs || '') +
      ' value="' + esc(typed[k] || '') + '">';
  }
  function paintForm() {
    var w = t();
    return '<div class="qs-step" data-shown><h1 class="qs-title">' + esc(w.title) + '</h1>' +
      '<p class="qs-lead">' + esc(f(w.for, { b: info.brand })) + '</p>' +
      '<form class="qs-form" id="dfForm" novalidate>' +
      '<section class="qs-sec"><h2 class="qs-sec-h">' + esc(w.company) + '</h2>' +
        // A name that may outrun its width wraps in the one-line box, in the capitals it is kept in.
        field('dfLegal', w.legal, true, '<textarea class="input qs-caps" id="dfLegal" data-k="legal_name" data-oneline aria-required="true" rows="1" maxlength="160" autocomplete="organization" placeholder="COMPANY NAME SDN BHD">' + esc(typed.legal_name || '') + '</textarea>') +
        field('dfBrn', w.brn, true, input('dfBrn', 'company_no', true, 'maxlength="24" inputmode="text" autocapitalize="characters" placeholder="202301234567"'), w.brnHint) +
        field('dfOld', w.old, false, input('dfOld', 'company_no_old', false, 'maxlength="24" autocapitalize="characters" placeholder="' + esc(w.optional) + '"')) +
        field('dfTin', w.tin, false, input('dfTin', 'tin', false, 'maxlength="24" autocapitalize="characters" placeholder="' + esc(w.optional) + '"')) +
        field('dfSst', w.sst, false, input('dfSst', 'sst_no', false, 'maxlength="30" autocapitalize="characters" placeholder="' + esc(w.optional) + '"')) +
        field('dfAddr', w.address, true, '<textarea class="input" id="dfAddr" data-k="billing_address" aria-required="true" rows="3" maxlength="400" autocomplete="street-address">' + esc(typed.billing_address || '') + '</textarea>') +
        field('dfFin', w.finance, false, input('dfFin', 'finance_email', false, 'type="email" maxlength="160" autocomplete="email" placeholder="' + esc(w.optional) + '"')) +
      '</section>' +
      '<section class="qs-sec"><h2 class="qs-sec-h">' + esc(w.contact) + '</h2>' +
        field('dfSal', w.sal, false, '<select class="select" id="dfSal" data-k="contact_salutation"><option value="">' + esc(w.optional) + '</option>' +
          SALUTATIONS.map(function (x) { return '<option value="' + esc(x) + '"' + (typed.contact_salutation === x ? ' selected' : '') + '>' + esc((lang === 'zh' && SAL_ZH[x]) || x) + '</option>'; }).join('') + '</select>') +
        field('dfName', w.name, true, input('dfName', 'contact_name', true, 'maxlength="80" autocomplete="name" placeholder="John Doe"')) +
        field('dfPhone', w.phone, true, input('dfPhone', 'contact_phone', true, 'type="tel" inputmode="tel" autocomplete="tel" placeholder="012-345 6789"')) +
        field('dfEmail', w.email, true, input('dfEmail', 'contact_email', true, 'type="email" maxlength="160" autocomplete="email" placeholder="email@adspace.me"')) +
      '</section>' +
      '<label class="qs-consent"><input type="checkbox" id="dfConsent"' + (consent ? ' checked' : '') + '>' + MARK + '<span class="qs-text">' + esc(w.consent) + '</span></label>' +
      '<span class="msg" id="dfConsentMsg"></span>' +
      '<p class="qs-note">' + esc(f(w.ends, { d: day(info.expires_at) })) + '</p>' +
      '<p class="msg" id="dfMsg" role="status"></p>' +
      '</form></div>' +
      '<div class="qs-foot"><button class="btn btn-primary" type="button" id="dfSubmit">' + esc(w.submit) + '</button></div>';
  }
  function paintDone(title, text) {
    root().innerHTML = '<div class="qs-step qs-done" data-shown><span class="qs-tick" aria-hidden="true">' +
      '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12 5 5 9-10"/></svg></span>' +
      '<h1 class="qs-title">' + esc(title) + '</h1><p>' + esc(text) + '</p></div>';
  }
  function paint() {
    document.documentElement.setAttribute('lang', lang === 'zh' ? 'zh' : 'en');
    if ($('langToggle')) $('langToggle').textContent = t().lang;
    var w = t();
    if (state === 'loading') return;
    if (state === 'bad') { cover(w.notFound, w.notFoundText); return; }
    if (state === 'fail') { cover(w.failTitle, w.failText); return; }
    if (state === 'expired') { cover(w.expT, w.notFoundText); return; }
    if (state === 'submitted') { cover(w.submittedT, w.submittedP); return; }
    if (state === 'done') { paintDone(w.doneT, w.doneP); return; }
    root().innerHTML = paintForm();
    if (window.ADspaceForm && window.ADspaceForm.scan) window.ADspaceForm.scan(root());
    if (window.ADspaceGrow && window.ADspaceGrow.fit) Array.prototype.forEach.call(root().querySelectorAll('textarea'), window.ADspaceGrow.fit);
  }
  function read() {
    Array.prototype.forEach.call(root().querySelectorAll('[data-k]'), function (el) { typed[el.getAttribute('data-k')] = el.value; });
    consent = Boolean($('dfConsent') && $('dfConsent').checked);
  }
  function say(id, text, tone) {
    var m = $(id); if (!m) return;
    m.textContent = text || ''; m.className = 'msg' + (text ? ' ' + (tone || 'err') : '');
  }
  var ID = { legal_name: 'dfLegal', company_no: 'dfBrn', company_no_old: 'dfOld', tin: 'dfTin', sst_no: 'dfSst',
    billing_address: 'dfAddr', finance_email: 'dfFin', contact_salutation: 'dfSal', contact_name: 'dfName',
    contact_phone: 'dfPhone', contact_email: 'dfEmail' };
  function check() {
    var w = t(), first = null, mail = { test: ADspaceWords.emailOk };
    var bad = function (k, text) {
      var id = ID[k] || k; say(id + 'Msg', text);
      if ($(id)) $(id).setAttribute('aria-invalid', 'true');
      if (!first) first = id;
    };
    Object.keys(ID).forEach(function (k) { say(ID[k] + 'Msg', ''); if ($(ID[k])) $(ID[k]).removeAttribute('aria-invalid'); });
    say('dfConsentMsg', '');
    var v = function (k) { return String(typed[k] || '').trim(); };
    if (v('legal_name').length < 2) bad('legal_name', w.req);
    var brn = v('company_no').replace(/\s+/g, '');
    if (!brn) bad('company_no', w.req); else if (!/^[A-Za-z0-9-]{6,20}$/.test(brn)) bad('company_no', w.badBrn);
    // The lengths client_details_submit holds each number to, so the page names what the database would refuse.
    Object.keys(CODE).forEach(function (k) {
      var x = v(k).replace(/\s+/g, '');
      if (x && !new RegExp('^[A-Za-z0-9-]{' + CODE[k][0] + ',' + CODE[k][1] + '}$').test(x)) bad(k, fault(k));
    });
    if (!v('billing_address')) bad('billing_address', w.req); else if (v('billing_address').length < 10 || v('billing_address').length > 400) bad('billing_address', w.badAddr);
    if (v('finance_email') && !mail.test(v('finance_email'))) bad('finance_email', w.badEmail);
    if (v('contact_name').length < 2) bad('contact_name', w.req);
    var digits = v('contact_phone').replace(/\D/g, '');
    if (!digits) bad('contact_phone', w.req); else if (digits.length < 8 || digits.length > 15) bad('contact_phone', w.badPhone);
    if (!v('contact_email')) bad('contact_email', w.req); else if (!mail.test(v('contact_email'))) bad('contact_email', w.badEmail);
    if (!consent) { say('dfConsentMsg', w.tick); if (!first) first = 'dfConsent'; }
    if (first && $(first)) $(first).focus();
    return !first;
  }
  var CODE = { company_no_old: [4, 20], tin: [6, 20], sst_no: [6, 25] };
  /* What a field's refusal says: its own fault, never "This is required." under an optional field. */
  function fault(k) {
    var w = t();
    if (CODE[k]) return f(w.badCode, { a: CODE[k][0], b: CODE[k][1] });
    return { company_no: w.badBrn, billing_address: w.badAddr, finance_email: w.badEmail, contact_email: w.badEmail,
      contact_phone: w.badPhone }[k] || w.req;
  }
  var SERVER = { 'bad-legal_name': 'legal_name', 'bad-company_no': 'company_no', 'bad-company_no_old': 'company_no_old',
    'bad-tin': 'tin', 'bad-sst_no': 'sst_no', 'bad-billing_address': 'billing_address', 'bad-finance_email': 'finance_email',
    'bad-contact_salutation': 'contact_salutation', 'bad-contact_name': 'contact_name', 'bad-contact_phone': 'contact_phone',
    'bad-contact_email': 'contact_email' };
  function submit(btn) {
    if (sending) return;
    read();
    if (!check()) return;
    sending = true; btn.disabled = true;
    var answers = {};
    FIELDS.forEach(function (k) { answers[k] = String(typed[k] || '').trim(); });
    db.rpc('client_details_submit', { p_key: key, p_answers: answers }).then(function (r) {
      var d = r.data || {};
      if (r.error) throw r.error;
      if (d.error === 'submitted') { state = 'submitted'; paint(); return; }
      if (d.error === 'expired') { state = 'expired'; paint(); return; }
      if (d.error === 'not_found') { state = 'bad'; paint(); return; }
      if (d.error && SERVER[d.error]) {
        var id = ID[SERVER[d.error]];
        if (SERVER[d.error] === 'contact_salutation') { say('dfMsg', t().notSent); return; }
        say(id + 'Msg', fault(SERVER[d.error]));
        if ($(id)) { $(id).setAttribute('aria-invalid', 'true'); $(id).focus(); }
        return;
      }
      if (d.error) throw new Error(d.error);
      state = 'done'; paint(); window.scrollTo(0, 0);
    }).catch(function () {
      say('dfMsg', t().notSent);
    }).then(function () { sending = false; if (btn && btn.isConnected) btn.disabled = false; });
  }

  document.addEventListener('click', function (e) {
    var b = e.target.closest('#dfSubmit');
    if (b) submit(b);
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && e.target && e.target.matches && e.target.matches('#dfForm input:not([type=checkbox]), #dfForm textarea[data-oneline]') && !e.isComposing) {
      e.preventDefault(); if ($('dfSubmit')) submit($('dfSubmit'));
    }
  });
  if ($('langToggle')) $('langToggle').addEventListener('click', function () {
    if (state === 'open') read();
    lang = lang === 'en' ? 'zh' : 'en';
    try { localStorage.setItem(LANG_KEY, lang); } catch (e) {}
    paint();
  });

  if (!db) { state = 'fail'; paint(); return; }
  if (!/^[a-z0-9]{8}$/.test(key)) { state = 'bad'; paint(); return; }
  db.rpc('client_details_read', { p_key: key }).then(function (r) {
    var d = r.data || {};
    if (r.error) throw r.error;
    if (d.error === 'expired') state = 'expired';
    else if (d.error === 'submitted') state = 'submitted';
    else if (d.error || !d.ok) state = 'bad';
    else { info = d; state = 'open'; }
    paint();
  }).catch(function () { state = 'fail'; paint(); });
})();
