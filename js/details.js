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
      lang: '中文', title: 'Company Details', for: '{b}',
      company: 'Company', legal: 'Registered Company Name', brn: 'Business Registration No.',
      brnPh: '12 digits', old: 'Old Registration No.', tin: 'Tax Identification Number (TIN)',
      sst: 'SST Registration No.', address: 'Billing address', finance: 'Finance email',
      contact: 'Billing contact', sal: 'Salutation', name: 'Name', phone: 'Mobile number', email: 'Email',
      optional: 'Optional', consent: 'I confirm that these details are correct and consent to ADspace keeping them for business purposes.',
      submit: 'Submit',
      req: { legal_name: 'Enter the Registered Company Name.', company_no: 'Enter the Business Registration Number.',
        billing_address: 'Enter the billing address.', contact_name: 'Enter the billing contact\'s name.',
        contact_phone: 'Enter the mobile number.', contact_email: 'Enter the email address.' },
      badEmail: 'Enter a valid email address.', 
      badAddr: 'Enter the full billing address.', badCode: 'Enter {a} to {b} letters or digits, as registered.',
      doneP: 'Thank you. ADspace will review your details.',
      /* The form in steps (2026-11-25, the approved canvas). */
      introP: 'Provide your company\'s billing details to ADspace.', billing: 'Billing',
      companyLine: 'Registered Company Name, Business Registration No., Old Registration No., Tax Identification Number (TIN) and SST Registration No.',
      billingLine: 'Billing address and finance email.', contactLine: 'Salutation, name, mobile number and email.',
      reviewLine: 'Confirm that the details are correct, then submit.',
      dfConfirmed: 'Billing details confirmed'
    },
    zh: {
      lang: 'EN', title: '公司资料', for: '{b}',
      company: '公司', legal: '公司注册名称', brn: '商业注册号码',
      brnPh: '12位数字', old: '旧注册号码', tin: '税务识别号（TIN）',
      sst: 'SST 注册号码', address: '账单地址', finance: '财务邮箱',
      contact: '账单联系人', sal: '称谓', name: '姓名', phone: '手机号码', email: '邮箱',
      optional: '选填', consent: '我确认以上资料无误，并同意 ADspace 保存这些资料作业务用途。',
      submit: '提交',
      req: { legal_name: '请填写公司注册名称。', company_no: '请填写商业注册号码。', billing_address: '请填写账单地址。',
        contact_name: '请填写账单联系人姓名。', contact_phone: '请填写手机号码。', contact_email: '请填写邮箱地址。' },
      badEmail: '请输入有效的邮箱地址。', 
      badAddr: '请填写完整的账单地址。', badCode: '请按注册资料填写{a}至{b}位字母或数字。',
      doneP: '谢谢。ADspace 将审阅这些资料。',
      introP: '请向 ADspace 提供贵公司的账单资料。', billing: '账单',
      companyLine: '公司注册名称、商业注册号码、旧注册号码、税务识别号（TIN）及 SST 注册号码。',
      billingLine: '账单地址及财务邮箱。', contactLine: '称谓、姓名、手机号码及邮箱。',
      reviewLine: '确认资料无误后提交。',
      dfConfirmed: '账单资料已确认'
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
  var MARK = '<span class="qs-mark" aria-hidden="true">' + window.ADspaceIcons.glyph('check', '', 'width="12" height="12"') + '</span>';

  var key = (new URLSearchParams(location.search).get('k') || '').trim().toLowerCase();
  var info = null, state = 'loading', typed = {}, consent = false, sending = false;
  /* The form in steps (the user, 2026-11-25): the opening page (0), then a
     step a section, the last reading the answers back before Submit. */
  var at = 0, sentAt = null, reqRef = '';
  var STEPS = [
    { glyph: 'building', name: 'company', line: 'companyLine', keys: ['legal_name', 'company_no', 'company_no_old', 'tin', 'sst_no'] },
    { glyph: 'pin', name: 'billing', line: 'billingLine', keys: ['billing_address', 'finance_email'] },
    { glyph: 'user', name: 'contact', line: 'contactLine', keys: ['contact_salutation', 'contact_name', 'contact_phone', 'contact_email'] },
    { glyph: 'check', name: 'stepReview', line: 'reviewLine', keys: ['consent'] }
  ];
  function stepOfKey(k) { for (var i = 0; i < STEPS.length; i++) if (STEPS[i].keys.indexOf(k) > -1) return i + 1; return STEPS.length; }
  var root = function () { return $('dfRoot'); };

  /* `named`: a day the reader waits on carries its weekday (js/clock.js). */
  function day(iso, named) {
    var C = window.ADspaceClock;
    if (C && C.date) return C.date(iso, { zh: lang === 'zh', long: true, named: named });
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
  function salWord(x) { return (lang === 'zh' && SAL_ZH[x]) || x; }
  function lead() { return esc(f(t().for, { b: info.brand })); }
  /* The opening page: what the form asks, step by step, and when it closes. */
  function paintIntro() {
    var w = t(), I = window.ADspaceIcons;
    return '<div class="qs-step qs-intro" data-shown><div class="qs-top"><h1 class="qs-title">' + esc(w.title) + '</h1>' +
      '<p class="qs-lead">' + lead() + '</p><p class="qs-intro-p">' + esc(w.introP) + '</p></div>' +
      '<section class="qs-sec"><h2 class="qs-sec-h">' + esc(w.stepExpect) + '</h2>' +
        I.stepCards(STEPS.map(function (x) { return { glyph: x.glyph, name: w[x.name], line: w[x.line] }; })) + '</section>' +
      '<p class="qs-note qs-time">' + I.svg('clock') + '<span>' + esc(f(w.formEnds, { d: day(info.expires_at, true) })) + '</span></p></div>' +
      '<div class="qs-foot"><button class="btn btn-primary" type="button" id="dfStart">' + esc(w.stepStart) + '</button></div>';
  }
  function stepBody(n) {
    var w = t();
    if (n === 1) return '<section class="qs-sec">' +
        // A name that may outrun its width wraps in the one-line box, in the capitals it is kept in.
        field('dfLegal', w.legal, true, '<textarea class="input qs-caps" id="dfLegal" data-k="legal_name" data-oneline aria-required="true" rows="1" maxlength="160" autocomplete="organization" placeholder="COMPANY NAME SDN BHD">' + esc(typed.legal_name || '') + '</textarea>') +
        field('dfBrn', w.brn, true, input('dfBrn', 'company_no', true, sg() ? 'maxlength="24" inputmode="text" autocapitalize="characters"'
          : 'data-shape="############" inputmode="numeric" placeholder="' + esc(w.brnPh) + '"')) +
        field('dfOld', w.old, false, input('dfOld', 'company_no_old', false, 'maxlength="24" autocapitalize="characters" placeholder="' + esc(w.optional) + '"')) +
        field('dfTin', w.tin, false, input('dfTin', 'tin', false, 'maxlength="24" autocapitalize="characters" placeholder="' + esc(w.optional) + '"')) +
        field('dfSst', w.sst, false, input('dfSst', 'sst_no', false, 'maxlength="30" autocapitalize="characters" placeholder="' + esc(w.optional) + '"')) +
      '</section>';
    if (n === 2) return '<section class="qs-sec">' +
        field('dfAddr', w.address, true, '<textarea class="textarea" id="dfAddr" data-k="billing_address" aria-required="true" rows="3" maxlength="400" autocomplete="street-address">' + esc(typed.billing_address || '') + '</textarea>') +
        field('dfFin', w.finance, false, input('dfFin', 'finance_email', false, 'type="email" maxlength="160" autocomplete="email" placeholder="' + esc(w.optional) + '"')) +
      '</section>';
    if (n === 3) return '<section class="qs-sec">' +
        field('dfSal', w.sal, false, '<select class="select" id="dfSal" data-k="contact_salutation"><option value="">' + esc(w.optional) + '</option>' +
          SALUTATIONS.map(function (x) { return '<option value="' + esc(x) + '"' + (typed.contact_salutation === x ? ' selected' : '') + '>' + esc(salWord(x)) + '</option>'; }).join('') + '</select>') +
        field('dfName', w.name, true, input('dfName', 'contact_name', true, 'maxlength="80" autocomplete="name" placeholder="John Doe"')) +
        field('dfPhone', w.phone, true, input('dfPhone', 'contact_phone', true, 'type="tel" inputmode="tel" autocomplete="tel" placeholder="012-345 6789"')) +
        field('dfEmail', w.email, true, input('dfEmail', 'contact_email', true, 'type="email" maxlength="160" autocomplete="email" placeholder="email@adspace.me"')) +
      '</section>';
    /* The answers read back, an empty one left out, then the consent. */
    return yours({ label: w.stepEdit, attrs: 'id="dfEdit"' }) +
      '<label class="qs-consent"><input type="checkbox" id="dfConsent"' + (consent ? ' checked' : '') + '>' + MARK + '<span class="qs-text">' + esc(w.consent) + '</span></label>' +
      '<span class="msg" id="dfConsentMsg"></span>' +
      '<p class="qs-note">' + esc(f(w.formEnds, { d: day(info.expires_at, true) })) + '</p>';
  }
  /* What was typed, read back: on the review step with Edit, and on the
     received page once sent. */
  function yours(edit) {
    var w = t(), v = function (k) { return String(typed[k] || '').trim(); };
    return window.ADspaceIcons.summary(w.yourDetails, [
        { name: w.company, rows: [[w.legal, v('legal_name').toUpperCase()], [w.brn, v('company_no')], [w.old, v('company_no_old')], [w.tin, v('tin')], [w.sst, v('sst_no')]] },
        { name: w.billing, rows: [[w.address, v('billing_address')], [w.finance, v('finance_email')]] },
        { name: w.contact, rows: [[w.name, (v('contact_salutation') ? salWord(v('contact_salutation')) + ' ' : '') + v('contact_name')], [w.phone, v('contact_phone')], [w.email, v('contact_email')]] }
      ], edit);
  }
  function paintForm() {
    var w = t(), I = window.ADspaceIcons, x = STEPS[at - 1], last = at === STEPS.length;
    return '<div class="qs-step" data-shown>' + I.stepTrack(at, STEPS.length, f(w.stepOf, { n: at, m: STEPS.length })) +
      I.stepHead(x.glyph, w[x.name], lead()) +
      '<form class="qs-form" id="dfForm" novalidate>' + stepBody(at) + '<p class="msg" id="dfMsg" role="status"></p></form></div>' +
      '<div class="qs-foot"><button class="btn qs-back" type="button" id="dfBack">' + esc(w.stepBack) + '</button>' +
      (last ? '<button class="btn btn-primary" type="button" id="dfSubmit">' + esc(w.submit) + '</button>'
        : '<button class="btn btn-primary" type="button" id="dfNext">' + esc(w.stepNext) + '</button>') + '</div>';
  }
  /* Received (the board ReceivedDetails, 2026-11-25; js/icons.js received):
     just sent, where it stands, what was sent and the account manager; a
     link opened again once sent, the statement alone. */
  function paintDone(title, text, sent) {
    var w = t(), I = window.ADspaceIcons, C = window.ADspaceClock, zh = lang === 'zh', rep = sent && info && info.rep;
    var when = sent && C ? C.date(sent, { zh: zh }) + (zh ? '' : ', ') + C.clock(sent, { zh: zh }) : '';
    var wa = rep && rep.whatsapp ? '<a class="btn btn-primary" href="https://wa.me/' + esc(rep.whatsapp) + '" target="_blank" rel="noopener">' +
      I.svg('whatsapp') + esc(w.chatWhatsApp) + '</a>' : '';
    root().innerHTML = I.received({
      /* The reference the database gave the submission (ONE REQUEST
         REFERENCE, 2026-11-26), on the page sent and on a link opened again. */
      title: title, line: text, ref: sent && info ? info.brand : '', reqRef: reqRef, reqLabel: (zh ? window.ADspaceWords.zh : window.ADspaceWords.en).coverRef,
      steps: sent ? [
        { state: 'done', title: w.detailsSent, sub: esc(when) },
        { state: 'now', glyph: 'search', title: w.rcvByAdspace, now: w.rcvNow },
        { glyph: 'verified', title: w.dfConfirmed }
      ] : [],
      cards: sent ? [yours(null), rep ? I.contactCard(w.representative, rep.name, rep.title, wa) : ''] : []
    });
  }
  function paint() {
    document.documentElement.setAttribute('lang', lang === 'zh' ? 'zh' : 'en');
    if ($('langToggle')) $('langToggle').textContent = t().lang;
    var w = t();
    if (state === 'loading') return;
    if (state === 'bad') { cover(w.notFound, w.notFoundText); return; }
    if (state === 'fail') { cover(w.failTitle, w.failText); return; }
    if (state === 'expired') { cover(w.linkExpired, w.notFoundText); return; }
    if (state === 'submitted') { paintDone(w.formReceived, w.formSubmitted); return; }
    if (state === 'done') { paintDone(w.formReceived, w.doneP, sentAt); return; }
    root().innerHTML = at ? paintForm() : paintIntro();
    if (window.ADspaceForm && window.ADspaceForm.scan) window.ADspaceForm.scan(root());
    if (window.ADspaceGrow && window.ADspaceGrow.fit) Array.prototype.forEach.call(root().querySelectorAll('textarea'), window.ADspaceGrow.fit);
  }
  function read() {
    Array.prototype.forEach.call(root().querySelectorAll('[data-k]'), function (el) { typed[el.getAttribute('data-k')] = el.value; });
    if ($('dfConsent')) consent = $('dfConsent').checked;
  }
  function say(id, text, tone) {
    var m = $(id); if (!m) return;
    m.textContent = text || ''; m.className = 'msg' + (text ? ' ' + (tone || 'err') : '');
  }
  var ID = { legal_name: 'dfLegal', company_no: 'dfBrn', company_no_old: 'dfOld', tin: 'dfTin', sst_no: 'dfSst',
    billing_address: 'dfAddr', finance_email: 'dfFin', contact_salutation: 'dfSal', contact_name: 'dfName',
    contact_phone: 'dfPhone', contact_email: 'dfEmail' };
  /* Every field's fault, in the form's order: [key, words]. The consent is
     the last step's. */
  function faults() {
    var w = t(), out = [], mail = ADspaceWords.emailOk;
    var bad = function (k, text) { out.push([k, text]); };
    var v = function (k) { return String(typed[k] || '').trim(); };
    if (v('legal_name').length < 2) bad('legal_name', w.req.legal_name);
    var brn = v('company_no').replace(/\s+/g, '');
    if (!brn) bad('company_no', w.req.company_no); else if (ADspaceWords.brnCheck(brn, sg() ? 'SG' : 'MY')) bad('company_no', fault('company_no'));
    // The lengths client_details_submit holds each number to, so the page names what the database would refuse.
    Object.keys(CODE).forEach(function (k) {
      var x = v(k).replace(/\s+/g, '');
      if (x && !new RegExp('^[A-Za-z0-9-]{' + CODE[k][0] + ',' + CODE[k][1] + '}$').test(x)) bad(k, fault(k));
    });
    if (!v('billing_address')) bad('billing_address', w.req.billing_address); else if (v('billing_address').length < 10 || v('billing_address').length > 400) bad('billing_address', w.badAddr);
    if (v('finance_email') && !mail(v('finance_email'))) bad('finance_email', w.badEmail);
    if (v('contact_name').length < 2) bad('contact_name', w.req.contact_name);
    var digits = v('contact_phone').replace(/\D/g, '');
    if (!digits) bad('contact_phone', w.req.contact_phone); else if (digits.length < 8 || digits.length > 15) bad('contact_phone', w.badMobile);
    if (!v('contact_email')) bad('contact_email', w.req.contact_email); else if (!mail(v('contact_email'))) bad('contact_email', w.badEmail);
    if (!consent) bad('consent', w.tickToContinue);
    return out;
  }
  /* The faults of the step on show, each under its field, the first focused. */
  function show(list) {
    var first = null;
    Object.keys(ID).forEach(function (k) { say(ID[k] + 'Msg', ''); if ($(ID[k])) $(ID[k]).removeAttribute('aria-invalid'); });
    say('dfConsentMsg', '');
    list.forEach(function (x) {
      var id = x[0] === 'consent' ? 'dfConsent' : ID[x[0]];
      if (!$(id)) return;
      say(id + 'Msg', x[1]);
      if (x[0] !== 'consent') $(id).setAttribute('aria-invalid', 'true');
      if (!first) first = id;
    });
    if (first) $(first).focus();
    return !first;
  }
  function stepFaults(n) { return faults().filter(function (x) { return STEPS[n - 1].keys.indexOf(x[0]) > -1; }); }
  function go(n) { at = n; paint(); window.scrollTo(0, 0); }
  /* Continue holds the step until its own fields are right. */
  function next() {
    read();
    if (!show(stepFaults(at))) return;
    go(at + 1);
  }
  /* Submit asks every step again: a fault takes the reader to its step. */
  function check() {
    var all = faults();
    if (!all.length) return true;
    var n = stepOfKey(all[0][0]);
    if (n !== at) go(n);
    show(stepFaults(n));
    return false;
  }
  /* The client's market picks the registration's shape: a Singapore
     client's UEN, every other client's 12-digit BRN (`client_details_read`). */
  function sg() { return !!(info && info.market === 'SG'); }
  var CODE = { company_no_old: [4, 20], tin: [6, 20], sst_no: [6, 25] };
  /* What a field's refusal says: its own fault, never "This is required." under an optional field. */
  function fault(k) {
    var w = t();
    if (CODE[k]) return f(w.badCode, { a: CODE[k][0], b: CODE[k][1] });
    return { company_no: ADspaceWords[lang === 'zh' ? 'zh' : 'en'][sg() ? 'uenBad' : 'brnBad'], billing_address: w.badAddr, finance_email: w.badEmail, contact_email: w.badEmail,
      contact_phone: w.badMobile }[k] || w.req[k] || w.req.legal_name;
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
      if (d.error === 'submitted') { reqRef = d.request_ref || ''; state = 'submitted'; paint(); return; }
      if (d.error === 'expired') { state = 'expired'; paint(); return; }
      if (d.error === 'not_found') { state = 'bad'; paint(); return; }
      if (d.error && SERVER[d.error]) {
        if (SERVER[d.error] === 'contact_salutation') { say('dfMsg', t().notSent); return; }
        go(stepOfKey(SERVER[d.error]));
        show([[SERVER[d.error], fault(SERVER[d.error])]]);
        return;
      }
      if (d.error) throw new Error(d.error);
      reqRef = d.request_ref || ''; state = 'done'; sentAt = new Date().toISOString(); paint(); window.scrollTo(0, 0);
    }).catch(function () {
      say('dfMsg', t().notSent);
    }).then(function () { sending = false; if (btn && btn.isConnected) btn.disabled = false; });
  }

  document.addEventListener('click', function (e) {
    if (!e.target.closest) return;
    var b = e.target.closest('#dfSubmit');
    if (b) { submit(b); return; }
    if (e.target.closest('#dfStart')) { go(1); return; }
    if (e.target.closest('#dfNext')) { next(); return; }
    if (e.target.closest('#dfBack')) { read(); go(at - 1); return; }
    if (e.target.closest('#dfEdit')) { read(); go(1); }
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && e.target && e.target.matches && e.target.matches('#dfForm input:not([type=checkbox]), #dfForm textarea[data-oneline]') && !e.isComposing) {
      /* Enter moves to the next field and only the last one submits, as the
         supplier's form does (2026-10-31, DET-2). */
      e.preventDefault();
      var all = Array.prototype.filter.call($('dfForm').querySelectorAll('input, select, textarea'), function (x) {
        return !x.disabled && x.offsetParent !== null && x.type !== 'hidden';
      });
      var to = all[all.indexOf(e.target) + 1];
      if (to) { to.focus(); return; }
      /* The step's last field goes on to the next step; the last step's submits. */
      if ($('dfSubmit')) submit($('dfSubmit')); else if ($('dfNext')) next();
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
    else if (d.error === 'submitted') { state = 'submitted'; reqRef = d.request_ref || ''; }
    else if (d.error || !d.ok) state = 'bad';
    else { info = d; state = 'open'; }
    paint();
  }).catch(function () { state = 'fail'; paint(); });
})();
