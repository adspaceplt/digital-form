/*
 * Personnel — a colleague's employee record (2026-11-16, Hiring and People
 * release H1; tests/hr-templates/HR-SPEC.md decisions 8 to 11).
 *
 *   * Team, a colleague's record, Personnel (`mtab=personnel`, the granted
 *     part `team.personnel`): the record form read first, sections A to H,
 *     its NRIC front and back and photograph, the employment terms, Edit in
 *     a sheet, Request employee record (a notice to the colleague).
 *   * My records, Personnel (`view=personnel`, behind the same fresh proof
 *     as the reviews): the colleague fills and updates their own, declared
 *     under their typed name with the consent tick, as the paper form.
 *   * The salary is never drawn but in its own sheet, after a caution step
 *     and the master-code unlock (the Performance pattern); never in a
 *     list, a notice, the Activity record or search.
 *   * Download for AutoCount (Team's ⋯): the AutoCount HRMS import in the
 *     template's exact layout (admin/hr/achrms-template.xlsx, js/xlsx.js),
 *     each value checked against AutoCount's lengths and lists before the
 *     file is made, never stored; each read filed by the database.
 *
 * What a reader is sent is the database's decision (`personnel_*`; no table
 * is readable directly).
 */
(function () {
  'use strict';
  var API = window.ADspaceAPI;
  var db = API && API.client;
  if (!API || !API.configured || !db) return;

  var $ = function (id) { return document.getElementById(id); };
  var bridge = window.ADspaceAdmin || {};
  function may(key, level) { return Boolean(bridge.may && bridge.may(key, level)); }
  function me() { return bridge.me ? bridge.me() : null; }
  function esc(s) { return window.ADspaceWords.esc(s); }
  var UI = window.ADspaceState;
  var PEN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>';
  var PLUS = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>';
  var LOCK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>';
  var FILE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M5 21h14"/></svg>';

  /* The form's fields, one list with the database's `personnel_fields()`
     (tests/personnel.js holds the two equal): section, key, label, kind,
     needed for the colleague's declaration. */
  var FIELDS = [
    ["a","full_name","Full Name as per NRIC","t:100",1],
    ["a","other_name","Other name or Chinese name","t:60",0],
    ["a","gender","Gender","e:Male|Female",1],
    ["a","birth_date","Date of birth","d",1],
    ["a","nationality","Nationality","t:60",1],
    ["a","nric","NRIC Number","t:20",0],
    ["a","old_ic","Old IC Number","t:15",0],
    ["a","passport","Passport Number","t:20",0],
    ["a","passport_expiry","Passport expiry date","d",0],
    ["a","immigration_no","Immigration Number","t:25",0],
    ["a","permit_expiry","Working Permit expiry date","d",0],
    ["a","race","Race","e:Malay|Chinese|Indian",0],
    ["a","religion","Religion","e:Islam|Buddhist|Hindu|Christian",0],
    ["a","disabled","Person with disability","b",0],
    ["a","address1","Address line 1","t:120",1],
    ["a","address2","Address line 2","t:120",0],
    ["a","postcode","Postal code","t:10",1],
    ["a","city","City","t:50",1],
    ["a","state","State","e:Johor|Kedah|Kelantan|Malacca|Negeri Sembilan|Others|Pahang|Penang|Perak|Perlis|Sabah|Sarawak|Selangor|Terengganu|Wilayah Persekutuan Kuala Lumpur|Wilayah Persekutuan Labuan|Wilayah Persekutuan Putrajaya",1],
    ["a","country","Country","t:60",1],
    ["a","email","Email","t:120",1],
    ["a","mobile","Mobile or WhatsApp","t:25",1],
    ["a","marital","Marital status","e:Single|Married|Divorced|Widowed",1],
    ["a","spouse_name","Spouse name","t:60",0],
    ["a","spouse_working","Spouse working","b",0],
    ["a","spouse_ic","Spouse NRIC Number","t:20",0],
    ["a","spouse_tax","Spouse Income Tax Number","t:20",0],
    ["a","spouse_phone","Spouse mobile","t:25",0],
    ["a","spouse_disabled","Spouse with disability","b",0],
    ["a","children_relief","Children claimed for tax relief","i:0:30",0],
    ["b","kin_name","Name as per NRIC","t:60",1],
    ["b","kin_relation","Relationship","e:Spouse|Child|Parent|Sibling",1],
    ["b","kin_mobile","Mobile or WhatsApp","t:25",1],
    ["b","kin_address1","Address line 1","t:120",0],
    ["b","kin_address2","Address line 2","t:120",0],
    ["b","kin_postcode","Postal code","t:10",0],
    ["b","kin_city","City","t:50",0],
    ["b","kin_state","State","t:50",0],
    ["b","kin_country","Country","t:60",0],
    ["c","bank","Bank","t:150",1],
    ["c","bank_account","Account number","t:30",1],
    ["c","bank_holder","Account holder name","t:60",1],
    ["c","epf_no","EPF Number","t:20",0],
    ["c","socso_no","SOCSO Number","t:12",0],
    ["c","tax_no","Income Tax Number","t:20",0],
    ["d","edu_primary_school","Primary: school","t:100",0],
    ["d","edu_primary_from","Primary: from","y",0],
    ["d","edu_primary_to","Primary: to","y",0],
    ["d","edu_primary_qual","Primary: highest qualification","t:100",0],
    ["d","edu_primary_results","Primary: results","t:60",0],
    ["d","edu_secondary_school","Secondary: school","t:100",0],
    ["d","edu_secondary_from","Secondary: from","y",0],
    ["d","edu_secondary_to","Secondary: to","y",0],
    ["d","edu_secondary_qual","Secondary: highest qualification","t:100",0],
    ["d","edu_secondary_results","Secondary: results","t:60",0],
    ["d","edu_college_school","College or Pre-U: school","t:100",0],
    ["d","edu_college_from","College or Pre-U: from","y",0],
    ["d","edu_college_to","College or Pre-U: to","y",0],
    ["d","edu_college_qual","College or Pre-U: highest qualification","t:100",0],
    ["d","edu_college_results","College or Pre-U: results","t:60",0],
    ["d","edu_university_school","University: school","t:100",0],
    ["d","edu_university_from","University: from","y",0],
    ["d","edu_university_to","University: to","y",0],
    ["d","edu_university_qual","University: highest qualification","t:100",0],
    ["d","edu_university_results","University: results","t:60",0],
    ["d","edu_professional_school","Professional: school","t:100",0],
    ["d","edu_professional_from","Professional: from","y",0],
    ["d","edu_professional_to","Professional: to","y",0],
    ["d","edu_professional_qual","Professional: highest qualification","t:100",0],
    ["d","edu_professional_results","Professional: results","t:60",0],
    ["d","training_1_course","Training 1: type of course","t:100",0],
    ["d","training_1_institution","Training 1: institution","t:100",0],
    ["d","training_1_qual","Training 1: qualification","t:100",0],
    ["d","training_1_year","Training 1: year","y",0],
    ["d","training_2_course","Training 2: type of course","t:100",0],
    ["d","training_2_institution","Training 2: institution","t:100",0],
    ["d","training_2_qual","Training 2: qualification","t:100",0],
    ["d","training_2_year","Training 2: year","y",0],
    ["d","training_3_course","Training 3: type of course","t:100",0],
    ["d","training_3_institution","Training 3: institution","t:100",0],
    ["d","training_3_qual","Training 3: qualification","t:100",0],
    ["d","training_3_year","Training 3: year","y",0],
    ["e","lang_en_spoken","English: spoken","e:Excellent|Good|Fair|Poor",0],
    ["e","lang_en_written","English: written","e:Excellent|Good|Fair|Poor",0],
    ["e","lang_zh_spoken","Chinese: spoken","e:Excellent|Good|Fair|Poor",0],
    ["e","lang_zh_written","Chinese: written","e:Excellent|Good|Fair|Poor",0],
    ["e","lang_ms_spoken","Malay: spoken","e:Excellent|Good|Fair|Poor",0],
    ["e","lang_ms_written","Malay: written","e:Excellent|Good|Fair|Poor",0],
    ["e","lang_other","Other language","t:30",0],
    ["e","lang_other_spoken","Other language: spoken","e:Excellent|Good|Fair|Poor",0],
    ["e","lang_other_written","Other language: written","e:Excellent|Good|Fair|Poor",0],
    ["e","typing","Typing","e:Fast|Normal|Slow",0],
    ["e","software","Software","m:Word|Excel|PowerPoint|Outlook",0],
    ["e","other_skills","Other skills","t:300",0],
    ["f","job_1_company","Employment 1: company","t:100",0],
    ["f","job_1_nature","Employment 1: nature of business","t:100",0],
    ["f","job_1_location","Employment 1: location","t:60",0],
    ["f","job_1_position","Employment 1: position","t:60",0],
    ["f","job_1_from","Employment 1: from","mo",0],
    ["f","job_1_to","Employment 1: to","mo",0],
    ["f","job_1_notes","Employment 1: notes and reason for leaving","t:500",0],
    ["f","job_2_company","Employment 2: company","t:100",0],
    ["f","job_2_nature","Employment 2: nature of business","t:100",0],
    ["f","job_2_location","Employment 2: location","t:60",0],
    ["f","job_2_position","Employment 2: position","t:60",0],
    ["f","job_2_from","Employment 2: from","mo",0],
    ["f","job_2_to","Employment 2: to","mo",0],
    ["f","job_2_notes","Employment 2: notes and reason for leaving","t:500",0],
    ["f","job_3_company","Employment 3: company","t:100",0],
    ["f","job_3_nature","Employment 3: nature of business","t:100",0],
    ["f","job_3_location","Employment 3: location","t:60",0],
    ["f","job_3_position","Employment 3: position","t:60",0],
    ["f","job_3_from","Employment 3: from","mo",0],
    ["f","job_3_to","Employment 3: to","mo",0],
    ["f","job_3_notes","Employment 3: notes and reason for leaving","t:500",0],
    ["g","heard","How they learned about ADspace","e:Newspaper ads|Friends or relatives|Websites|Career fair",0],
    ["g","applied_before","Applied to ADspace before","b",0],
    ["g","relative","Relative or friend at ADspace","b",0],
    ["g","relative_name","Relative or friend: name and relationship","t:100",0],
    ["g","convicted","Convicted of a criminal offence","b",0],
    ["g","conviction_note","Conviction details","t:500",0],
    ["g","licence","Driving licence","b",0],
    ["g","transport","Transport to work","t:60",0],
    ["h","ref_1_name","Reference 1: name","t:60",0],
    ["h","ref_1_title","Reference 1: title","t:60",0],
    ["h","ref_1_company","Reference 1: company","t:100",0],
    ["h","ref_1_address","Reference 1: short address","t:150",0],
    ["h","ref_1_phone","Reference 1: contact number","t:25",0],
    ["h","ref_2_name","Reference 2: name","t:60",0],
    ["h","ref_2_title","Reference 2: title","t:60",0],
    ["h","ref_2_company","Reference 2: company","t:100",0],
    ["h","ref_2_address","Reference 2: short address","t:150",0],
    ["h","ref_2_phone","Reference 2: contact number","t:25",0]
  ];
  var SECTIONS = [['a', 'Personal information'], ['b', 'Next of kin'], ['c', 'Payroll information'],
    ['d', 'Education'], ['e', 'Skills'], ['f', 'Previous employment'], ['g', 'General information'], ['h', 'References']];
  /* AutoCount's own lists (the template's Data sheet). */
  var COUNTRIES = ["Afghanistan", "Aland Islands", "Albania", "Algeria", "American Samoa", "Andorra", "Angola", "Anguilla", "Antarctica", "Antigua And Barbuda", "Argentina", "Armenia", "Aruba", "Australia", "Austria", "Azerbaijan", "Bahamas The", "Bahrain", "Bangladesh", "Barbados", "Belarus", "Belgium", "Belize", "Benin", "Bermuda", "Bhutan", "Bolivia", "Bonaire, Sint Eustatius and Saba", "Bosnia and Herzegovina", "Botswana", "Bouvet Island", "Brazil", "British Indian Ocean Territory", "Brunei", "Bulgaria", "Burkina Faso", "Burundi", "Cambodia", "Cameroon", "Canada", "Cape Verde", "Cayman Islands", "Central African Republic", "Chad", "Chile", "China", "Christmas Island", "Cocos (Keeling) Islands", "Colombia", "Comoros", "Congo", "Congo The Democratic Republic Of The", "Cook Islands", "Costa Rica", "Cote D'Ivoire (Ivory Coast)", "Croatia (Hrvatska)", "Cuba", "Cura\u00e7ao", "Cyprus", "Czech Republic", "Denmark", "Djibouti", "Dominica", "Dominican Republic", "East Timor", "Ecuador", "Egypt", "El Salvador", "Equatorial Guinea", "Eritrea", "Estonia", "Ethiopia", "Falkland Islands", "Faroe Islands", "Fiji Islands", "Finland", "France", "French Guiana", "French Polynesia", "French Southern Territories", "Gabon", "Gambia The", "Georgia", "Germany", "Ghana", "Gibraltar", "Greece", "Greenland", "Grenada", "Guadeloupe", "Guam", "Guatemala", "Guernsey and Alderney", "Guinea", "Guinea-Bissau", "Guyana", "Haiti", "Heard Island and McDonald Islands", "Honduras", "Hong Kong S.A.R.", "Hungary", "Iceland", "India", "Indonesia", "Iran", "Iraq", "Ireland", "Israel", "Italy", "Jamaica", "Japan", "Jersey", "Jordan", "Kazakhstan", "Kenya", "Kiribati", "Korea North", "Korea South", "Kosovo", "Kuwait", "Kyrgyzstan", "Laos", "Latvia", "Lebanon", "Lesotho", "Liberia", "Libya", "Liechtenstein", "Lithuania", "Luxembourg", "Macau S.A.R.", "Macedonia", "Madagascar", "Malawi", "Malaysia", "Maldives", "Mali", "Malta", "Man (Isle of)", "Marshall Islands", "Martinique", "Mauritania", "Mauritius", "Mayotte", "Mexico", "Micronesia", "Moldova", "Monaco", "Mongolia", "Montenegro", "Montserrat", "Morocco", "Mozambique", "Myanmar", "Namibia", "Nauru", "Nepal", "Netherlands The", "New Caledonia", "New Zealand", "Nicaragua", "Niger", "Nigeria", "Niue", "Norfolk Island", "Northern Mariana Islands", "Norway", "Oman", "Pakistan", "Palau", "Palestinian Territory Occupied", "Panama", "Papua new Guinea", "Paraguay", "Peru", "Philippines", "Pitcairn Island", "Poland", "Portugal", "Puerto Rico", "Qatar", "Reunion", "Romania", "Russia", "Rwanda", "Saint Helena", "Saint Kitts And Nevis", "Saint Lucia", "Saint Pierre and Miquelon", "Saint Vincent And The Grenadines", "Saint-Barthelemy", "Saint-Martin (French part)", "Samoa", "San Marino", "Sao Tome and Principe", "Saudi Arabia", "Senegal", "Serbia", "Seychelles", "Sierra Leone", "Singapore", "Sint Maarten (Dutch part)", "Slovakia", "Slovenia", "Solomon Islands", "Somalia", "South Africa", "South Georgia", "South Sudan", "Spain", "Sri Lanka", "Sudan", "Suriname", "Svalbard And Jan Mayen Islands", "Swaziland", "Sweden", "Switzerland", "Syria", "Taiwan", "Tajikistan", "Tanzania", "Thailand", "Togo", "Tokelau", "Tonga", "Trinidad And Tobago", "Tunisia", "Turkey", "Turkmenistan", "Turks And Caicos Islands", "Tuvalu", "Uganda", "Ukraine", "United Arab Emirates", "United Kingdom", "United States", "United States Minor Outlying Islands", "Uruguay", "Uzbekistan", "Vanuatu", "Vatican City State (Holy See)", "Venezuela", "Vietnam", "Virgin Islands (British)", "Virgin Islands (US)", "Wallis And Futuna Islands", "Western Sahara", "Yemen", "Zambia", "Zimbabwe"];
  var BANKS = ["Arab-Malaysian Bank Berhad", "Alliance Bank Berhad", "Al-Rajhi Banking and Investment Corporation (M) Bhd", "Affin Bank Berhad", "Agro Bank", "Bank Muamalat Malaysia Berhad", "Bank Islam Malaysia Berhad", "Bank Kerjasama Rakyat Berhad", "Bank Simpanan Nasional Berhad", "Bank of America Malaysia Berhad", "Bank of Tokyo-Mitsubishi UFJ (Malaysia) Berhad", "BNP Paribas (M) Bhd / BNP Paribas (M) Bhd (Islamic)", "CIMB Bank Berhad", "Citibank", "Deutsche Bank (M) Bhd", "Eon Bank Berhad/ Eon Finance Berhad", "Hong Leong Bank Bhd", "HSBC Bank Berhad", "Indust & Comm Bank of China (M) Berhad", "JP Morgan Chase Bank Berhad", "Kuwait Finance House Malaysia Berhad", "Malayan Banking Berhad", "Mizuho Bank (M) Berhad", "OCBC Bank Berhad", "Public Bank Bhd / Public Finance", "RHB Bank Berhad", "Standard Chartered Bank Bhd", "Sumitomo Mitsui Banking Corporation (M) Bhd", "The Royal Bank of Scotland Bhd", "United Overseas Bank (M) Bhd", "Affin Islamic Bank Berhad", "Alliance Islamic Bank Berhad", "CIMB Islamic Bank", "Hong Leong Islamic Bank Bhd", "MayBank Islamic Berhad", "OCBC AL-AMIN Bank Berhad", "RHB Islamic Bank Berhad", "Public Islamic Bank Bhd", "Bank Of China (M) Bhd", "AmBank Islamic Berhad", "HSBC Amanah Malaysia Berhad", "Standard Chartered SAADIQ Berhad", "Merchantrade Asia Sdn Bhd", "GX Bank Berhad", "Touch 'n Go", "MBSB Bank Berhad", "BigPay", "Boost", "Aeon Bank", "Boost Bank", "RYT BANK BHD", "China Construction Bank (Malaysia) Berhad"];
  var STATUSES = ['Management of the organization', 'Permanent', 'Contract', 'Part time', 'Interns', 'Others'];
  var TYPES = [['FT', 'Full time (FT)'], ['PT', 'Part time (PT)'], ['CT', 'Contract (CT)']];
  /* An employee status's usual type, offered while the type is unset. */
  var TYPE_OF = { 'Management of the organization': 'FT', Permanent: 'FT', Contract: 'CT', 'Part time': 'PT', Interns: 'CT', Others: 'CT' };
  var FILES = [['nric_front', 'NRIC (front)'], ['nric_back', 'NRIC (back)'], ['photo', 'Photograph']];

  var SAID = {
    denied: 'You do not have permission to open employee records. Please ask an admin.',
    'not-found': 'This colleague no longer exists.',
    'not-team': 'Only a team member can open this.',
    'bad-field': 'Enter a valid value.',
    incomplete: 'Fill in every required field.',
    'no-consent': 'Tick the consent to submit.',
    'bad-name': 'Type your full name to sign the declaration.',
    stale: 'Not saved. This record was changed by someone else. The latest version is now shown.',
    erased: 'This colleague\'s details were erased.',
    inactive: 'An employee record can be requested only from an active colleague.',
    own: 'Fill in your own record from My records.',
    'own-salary': 'You do not have permission to change your own salary. Please ask an admin.',
    'bad-status': 'Choose an employee status.', 'bad-type': 'Choose an employee type.',
    'bad-probation': 'Enter a probation of 0 to 12 months.', 'bad-date': 'Choose a join date from 14 Aug 2023.',
    'bad-end': 'The end of contract must be after the join date.', 'bad-superior': 'A colleague cannot report to themselves. Choose another colleague.',
    'bad-amount': 'Enter an amount of RM 0 or more.',
    'bad-kind': 'Choose a file to add.', 'bad-key': 'The file could not be saved. Try again.', 'not-kept': 'No file has been added.',
    'code-needed': 'Enter the master code.', 'no-code': 'The master code is not set. Please contact an admin.',
    'wrong-code': 'The master code is incorrect. Enter it again.', locked: 'Too many attempts. Try again in 15 minutes.',
    'bad-value': 'Choose a value from the list.', 'bad-field': 'This value cannot be shown. Refresh the page.', 'bad-code': 'Enter an AutoCount code of 2 to 10 letters or digits.',
    taken: 'This AutoCount code is already used by another department.'
  };
  function said(d) {
    if (!d || !d.error) return '';
    if (d.error === 'db') {
      return /Could not find the function|schema cache|PGRST202/i.test(d.message || '')
        ? window.ADspaceWords.line.notYet : 'Not saved. Please try again.';
    }
    if (d.error === 'wrong-code' && d.left) return SAID['wrong-code'] + ' ' + d.left + (d.left === 1 ? ' attempt' : ' attempts') + ' left.';
    return SAID[d.error] || 'Not saved. Please try again.';
  }
  function call(fn, args, then) {
    var done = false;
    var back = function (d) { if (done) return; done = true; then(d || {}); };
    try {
      db.rpc(fn, args || {}).then(function (r) {
        if (r.error) { back({ error: 'db', message: r.error.message }); return; }
        back(r.data || {});
      }).catch(function (e) { back({ error: 'db', message: String((e && e.message) || e) }); });
    } catch (e) { back({ error: 'db', message: String((e && e.message) || e) }); }
  }
  /* The colleague's own calls go through My records' call, so a proof gone
     stale puts the lock back over My records. */
  function mineCall(fn, args, then) {
    var P = window.ADspacePerf;
    if (P && P.mineCall) P.mineCall(fn, args, then); else call(fn, args, then);
  }
  function msg(el, text, kind) {
    if (typeof el === 'string') el = $(el);
    if (!el) return;
    el.textContent = text || ''; el.className = 'msg' + (text ? ' ' + (kind || 'err') : '');
  }
  function dateWord(s) { return s ? (window.ADspaceClock.date(String(s).slice(0, 10)) || String(s)) : ''; }
  function monthWord(s) {
    if (!/^\d{4}-\d{2}$/.test(s || '')) return s || '';
    return window.ADspaceClock.month ? window.ADspaceClock.month(s + '-01') : s;
  }
  function field(k) { return FIELDS.filter(function (f) { return f[1] === k; })[0]; }
  function labelOf(k) { var f = field(k); return f ? f[2] : k; }
  /* A label inside a sentence: its first letter lower, but an official
     term keeps its capitals (Full Name as per NRIC, NRIC Number). */
  function lowerFirst(l) {
    var w = String(l).split(' ');
    return /^[A-Z]{2}/.test(l) || (w[1] && /^[A-Z]/.test(w[1])) ? l : l.charAt(0).toLowerCase() + l.slice(1);
  }
  function valueWord(f, v) {
    if (v === undefined || v === null || v === '') return '';
    var kind = f[3];
    if (kind === 'b') return v ? 'Yes' : 'No';
    if (kind === 'd') return dateWord(v);
    if (kind === 'mo') return monthWord(v);
    if (kind.indexOf('m:') === 0) return (v || []).join(', ');
    return String(v);
  }

  // ---- Reading a record --------------------------------------------------------------
  /* The record read first: a group a section, each answer as a fact; a
     required answer missing reads Not set in warn. */
  function readSections(rec) {
    var data = rec.data || {}, miss = rec.missing || [];
    return SECTIONS.map(function (s) {
      var rows = FIELDS.filter(function (f) { return f[0] === s[0]; }).filter(function (f) {
        if (/^spouse_/.test(f[1]) && data.marital !== 'Married') return false;
        return valueWord(f, data[f[1]]) || miss.indexOf(f[1]) > -1;
      });
      var inner = rows.length ? '<dl class="ovfacts">' + rows.map(function (f) {
        var w = valueWord(f, data[f[1]]);
        if (w && HIDDEN.indexOf(f[1]) > -1) return secretFact(f, w);
        return '<div><dt>' + esc(f[2]) + '</dt><dd' + (w ? '' : ' class="is-missing"') + '>' + esc(w || 'Not set') + '</dd></div>';
      }).join('') + '</dl>' : '<p class="prs-none">Not set</p>';
      return group(s[1], inner);
    }).join('');
  }
  // ---- Hidden values (PERSONAL DETAILS REVEALED, 2026-11-25) -------------------------
  /* The most sensitive answers start hidden, dots and their last four
     characters; the eye at the value's right edge shows one only once the
     database has filed it (`personnel_revealed`: its label, never the
     value). A value shown hides again after `reveal_seconds` (a Business
     setting), when the page is left or hidden, and on every redraw. Editing
     in the sheet shows the real values, as before. */
  var HIDDEN = ['nric', 'old_ic', 'passport', 'immigration_no', 'spouse_ic', 'spouse_tax', 'bank_account', 'epf_no', 'socso_no', 'tax_no'];
  function masked(w) { var s = String(w); return '•••• ' + (s.length > 4 ? s.slice(-4) : ''); }
  function eyeGlyph(shown) {
    return shown ? window.ADspaceActs.glyph('hide') : window.ADspaceIcons.svg('eye');
  }
  function secretFact(f, w) {
    return '<div class="prs-secret"><dt>' + esc(f[2]) + '</dt><dd><span class="prs-secret-v" data-secret="' + esc(f[1]) + '">' + esc(masked(w)) + '</span>' +
      '<button class="iconbtn prs-eye" type="button" data-eye="' + esc(f[1]) + '" aria-pressed="false" aria-label="Show ' + esc(f[2]) + '">' +
      eyeGlyph(false) + '</button></dd></div>';
  }
  var shownTimers = [];
  function hideAll(box) {
    shownTimers.forEach(clearTimeout); shownTimers = [];
    Array.prototype.forEach.call((box || document).querySelectorAll('.prs-eye[aria-pressed="true"]'), function (b) { setShown(b, null); });
  }
  function setShown(b, value) {
    var k = b.getAttribute('data-eye'), f = field(k), v = b.parentNode.querySelector('[data-secret]');
    var on = value != null;
    v.textContent = on ? value : masked(v.getAttribute('data-real') || '');
    if (!on) v.removeAttribute('data-real');
    b.setAttribute('aria-pressed', on ? 'true' : 'false');
    b.setAttribute('aria-label', (on ? 'Hide ' : 'Show ') + (f ? f[2] : k));
    b.innerHTML = eyeGlyph(on);
  }
  function revealSeconds() {
    var M = window.ADspaceMoney, C = window.ADspaceClock;
    var n = M && M.setting && C ? Number(M.setting('reveal_seconds', C.today())) : NaN;
    return n > 0 ? n : null;
  }
  function wireEyes(box, rec, member, line) {
    Array.prototype.forEach.call(box.querySelectorAll('.prs-eye'), function (b) {
      b.addEventListener('click', function () {
        var k = b.getAttribute('data-eye');
        if (b.getAttribute('aria-pressed') === 'true') { setShown(b, null); return; }
        var real = valueWord(field(k), (rec.data || {})[k]);
        b.disabled = true;
        (member ? call : mineCall)('personnel_revealed', { p_member: member || null, p_field: k }, function (d) {
          b.disabled = false;
          if (d.error) { msg(line, said(d)); return; }
          msg(line, '');
          b.parentNode.querySelector('[data-secret]').setAttribute('data-real', real);
          setShown(b, real);
          var secs = revealSeconds();
          if (secs) shownTimers.push(setTimeout(function () { if (b.isConnected) setShown(b, null); }, secs * 1000));
        });
      });
    });
  }
  /* A page left, or put behind another, hides every value shown. */
  document.addEventListener('visibilitychange', function () { if (document.hidden) hideAll(); });
  window.addEventListener('pagehide', function () { hideAll(); });

  function group(title, inner, act) {
    return '<section class="readgroup"><div class="readgroup-head"><h4 class="fsec-h">' + esc(title) + '</h4>' + (act || '') + '</div>' + inner + '</section>';
  }
  function fact(label, value, warn) {
    return '<div><dt>' + esc(label) + '</dt><dd' + (value ? '' : ' class="' + (warn ? 'is-missing' : 'is-empty') + '"') + '>' + esc(value || 'Not set') + '</dd></div>';
  }
  function statusGroup(rec, team, act) {
    var miss = (rec.missing || []).length;
    var facts = fact('Declaration', rec.declared_at ? 'Signed by ' + rec.declared_name + ' on ' + dateWord(rec.declared_at) : 'Not submitted', !rec.declared_at) +
      (team && rec.requested_at ? fact('Requested', dateWord(rec.requested_at)) : '') +
      (rec.updated_at ? fact('Last changed', dateWord(rec.updated_at) + (rec.updated_by ? ' by ' + rec.updated_by : '')) : '');
    return group('Employee record', '<dl class="ovfacts">' + facts + '</dl>' +
      (miss ? '<p class="msg warn prs-miss">' + miss + (miss === 1 ? ' required field is' : ' required fields are') + ' not filled in.</p>' : ''), act);
  }
  function filesGroup(rec, can) {
    var files = rec.files || {};
    return group('Documents', '<div class="prs-files">' + FILES.map(function (k) {
      var f = files[k[0]];
      return '<div class="prs-file" data-file="' + k[0] + '"><div class="prs-file-who"><span class="prs-file-name">' + esc(k[1]) + '</span>' +
        '<span class="prs-file-meta">' + esc(f ? 'Added ' + dateWord(f.at) : 'Not added') + '</span></div>' +
        '<span class="prs-file-acts">' +
          (f ? '<button class="btn btn-sm" type="button" data-f="view">Preview</button>' : '') +
          (can ? '<label class="btn btn-sm prs-pick">' + (f ? 'Replace' : PLUS + 'Add') +
            '<input type="file" accept="' + (k[0] === 'photo' ? 'image/jpeg,image/png' : 'image/jpeg,image/png,application/pdf') + '" data-f="pick" hidden></label>' : '') +
          (f && can ? '<span class="team-act"><button class="kmenu-btn" type="button" data-f="menu" aria-label="More actions for ' + esc(k[1]) + '" aria-expanded="false">' +
            '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/></svg></button>' +
            '<div class="kmenu" data-menu hidden role="menu"><button class="kmenu-item is-danger" data-g="6" type="button" role="menuitem" data-f="remove">Delete</button></div></span>' : '') +
        '</span></div>';
    }).join('') + '</div><div class="msg" data-fmsg></div>');
  }
  function termsGroup(rec, team) {
    var sup = rec.superior_id && (team.people || []).filter(function (t) { return t.id === rec.superior_id; })[0];
    var superior = sup ? sup.name : '';
    var facts = fact('Join date', dateWord(rec.join_date)) +
      fact('Employee status', rec.employee_status) +
      fact('Employee type', (TYPES.filter(function (t) { return t[0] === rec.employee_type; })[0] || [])[1]) +
      fact('Probation', rec.probation_months == null ? '' : rec.probation_months === 0 ? 'None' : rec.probation_months + (rec.probation_months === 1 ? ' month' : ' months')) +
      fact('Confirm date', dateWord(rec.confirm_date)) +
      (rec.contract_end ? fact('End of contract', dateWord(rec.contract_end)) : '') +
      (team ? fact('Reports to', superior) : '');
    return group('Employment terms', '<dl class="ovfacts">' + facts + '</dl>',
      team ? '<button class="btn btn-sm" type="button" data-p="terms">' + PEN + 'Edit</button>' : '');
  }
  function salaryGroup(rec) {
    return group('Salary', '<dl class="ovfacts"><div><dt>Salary</dt><dd class="prs-locked">' + LOCK +
      esc(rec.salary_set ? 'Set (master code required)' : 'Not set') + '</dd></div></dl>',
      '<button class="btn btn-sm" type="button" data-p="salary">View</button>');
  }

  // ---- Team: a colleague's Personnel tab ---------------------------------------------
  var team = { m: null, host: null, rec: null, live: null, probation: null, people: [] };
  function paneTeam(m, host, live, people) {
    team.people = people || [];
    team.m = m; team.host = host; team.live = live;
    if (!team.rec || team.rec.member !== m.id) team.rec = null;
    host.innerHTML = '<div class="panel mrec-card prs-card" data-trace><div class="msg" id="prsMsg"></div><div id="prsBox"></div></div>';
    if (!team.rec) UI.skeleton($('prsBox'), 4);
    call('personnel_get', { p_member: m.id }, function (d) {
      if (!live()) return;
      if (d.error) { UI.failLine($('prsBox'), 'The employee record', said(d), function () { paneTeam(m, host, live, people); }); return; }
      team.rec = d;
      paintTeam();
      /* The bell's probation notice opens here behind the caution and the
         unlock (decision 11). */
      if (team.probation === m.id) { team.probation = null; salaryOpen(null); }
    });
  }
  function paintTeam() {
    var box = $('prsBox'), rec = team.rec, m = team.m;
    if (!box || !rec) return;
    hideAll();
    var self = me() && me().id === m.id;
    var acts = '<div class="prs-acts">' +
      (!self && m.active && !m.system ? '<button class="btn btn-sm" type="button" data-p="request">Request employee record</button>' : '') +
      (isAdmin() && window.ADspaceHrForms ? '<button class="btn btn-sm" type="button" data-p="pdf">Download</button>' : '') +
      '<button class="btn btn-sm" type="button" data-p="edit">' + PEN + 'Edit</button></div>';
    box.innerHTML = '<div class="readgroups">' +
      statusGroup(rec, true, acts) +
      termsGroup(rec, true) + salaryGroup(rec) + filesGroup(rec, true) + readSections(rec) + '</div>';
    wire(box, rec, m.id);
    wireEyes(box, rec, m.id, 'prsMsg');
  }
  function wire(box, rec, member) {
    Array.prototype.forEach.call(box.querySelectorAll('[data-p]'), function (b) {
      b.addEventListener('click', function () {
        var k = b.getAttribute('data-p');
        if (k === 'edit') openForm(rec, member, b);
        if (k === 'terms') openTerms(b);
        if (k === 'salary') salaryOpen(b);
        if (k === 'request') request(b);
        if (k === 'pdf') window.ADspaceHrForms.download(b, 'record', team.m.name, recordForm, $('prsMsg'));
      });
    });
    wireFiles(box, member);
  }
  /* The Employee Record Form as the paper reads it (js/hrforms.js): every
     answer a section, the terms (never the salary), the declaration, the
     photograph at the head and the NRIC copies at the foot. */
  function isAdmin() { var A = window.ADspaceAdmin; return Boolean(A && A.isAdmin && A.isAdmin()); }
  function fileBlob(member, kind) {
    return db.functions.invoke('sign-download', { body: { personnel: { member: member, kind: kind } } }).then(function (r) {
      if (!r || r.error) return null;
      return window.ADspaceAPI.fileOf(r.data).then(function (b) { return b && /^image\//.test(b.type) ? b : null; });
    }).catch(function () { return null; });
  }
  function recordForm() {
    var rec = team.rec, m = team.m, data = rec.data || {}, files = rec.files || {};
    var sup = rec.superior_id && team.people.filter(function (t) { return t.id === rec.superior_id; })[0];
    var sections = [{ h: 'Employment terms', rows: [
      ['Join date', dateWord(rec.join_date)], ['Employee status', rec.employee_status],
      ['Employee type', (TYPES.filter(function (t) { return t[0] === rec.employee_type; })[0] || [])[1]],
      ['Probation', rec.probation_months == null ? '' : rec.probation_months === 0 ? 'None' : rec.probation_months + (rec.probation_months === 1 ? ' month' : ' months')],
      ['Confirm date', dateWord(rec.confirm_date)]
    ].concat(rec.contract_end ? [['End of contract', dateWord(rec.contract_end)]] : []).concat([['Reports to', sup ? sup.name : '']]) }];
    SECTIONS.forEach(function (s) {
      var rows = FIELDS.filter(function (f) { return f[0] === s[0]; }).filter(function (f) {
        return !(/^spouse_/.test(f[1]) && data.marital !== 'Married') && valueWord(f, data[f[1]]);
      }).map(function (f) { return [f[2], valueWord(f, data[f[1]])]; });
      sections.push(rows.length ? { h: s[1], rows: rows } : { h: s[1], lines: ['Not set'] });
    });
    sections.push({ h: 'Declaration', lines: [rec.declared_at ? 'Signed by ' + rec.declared_name + ' on ' + dateWord(rec.declared_at) + '.' : 'Not submitted.'] });
    var want = function (k) { return files[k] ? fileBlob(m.id, k) : Promise.resolve(null); };
    return Promise.all([want('photo'), want('nric_front'), want('nric_back')]).then(function (b) {
      return { title: 'Employee Record Form', who: m.name, ref: [m.staff_code, m.designation].filter(Boolean).join(' · '),
        sections: sections, photo: b[0],
        images: [{ label: 'NRIC (front)', blob: b[1] }, { label: 'NRIC (back)', blob: b[2] }] };
    });
  }
  function setRec(d) {
    if (team.m && d.member === team.m.id) { team.rec = d; paintTeam(); }
    if (mine.rec && d.member === mine.rec.member) { mine.rec = d; paintMine(); }
  }
  function request(b) {
    var m = team.m;
    window.ADspaceConfirm.ask({ title: 'Request employee record?', body: m.name + ' will be asked to fill in their employee record in My records.', go: 'Request', wait: true },
      function () {
        return new Promise(function (ok) {
          call('personnel_request', { p_member: m.id }, function (d) {
            if (d.error) { ok(said(d)); return; }
            team.rec.requested_at = d.requested_at; paintTeam(); msg('prsMsg', 'Requested.', 'ok'); ok('');
          });
        });
      });
  }

  // ---- The form sheet ----------------------------------------------------------------
  var form = { member: null, own: false, rec: null };
  function inputOf(f, v) {
    var k = f[1], kind = f[3], id = 'prs_' + k, req = f[4] && form.own;
    var lab = '<label class="field-label" for="' + id + '">' + esc(f[2]) + '</label>';
    var ar = req ? ' aria-required="true"' : '';
    var val = v == null ? '' : v;
    if (kind === 'b') {
      return '<div>' + lab + '<select class="select" id="' + id + '" data-k="' + k + '">' +
        [['', 'Choose'], ['yes', 'Yes'], ['no', 'No']].map(function (o) {
          var on = (o[0] === 'yes' && v === true) || (o[0] === 'no' && v === false) || (o[0] === '' && v == null);
          return '<option value="' + o[0] + '"' + (on ? ' selected' : '') + '>' + o[1] + '</option>';
        }).join('') + '</select></div>';
    }
    if (kind.indexOf('e:') === 0 || k === 'nationality' || k === 'country' || k === 'bank') {
      var list = k === 'bank' ? BANKS : (k === 'nationality' || k === 'country') ? COUNTRIES : kind.slice(2).split('|');
      /* Every list opens on Choose: a segment always holds an answer, and
         an answer nobody gave is never saved. */
      return '<div>' + lab + '<select class="select" id="' + id + '" data-k="' + k + '"' + ar + '>' +
        '<option value="">Choose</option>' +
        list.map(function (o) { return '<option' + (o === val ? ' selected' : '') + '>' + esc(o) + '</option>'; }).join('') + '</select></div>';
    }
    if (kind.indexOf('m:') === 0) {
      return '<div class="span-all"><span class="field-label">' + esc(f[2]) + '</span><div class="prs-ticks">' + kind.slice(2).split('|').map(function (o) {
        return '<label class="tickline"><input type="checkbox" data-k="' + k + '" value="' + esc(o) + '"' + ((v || []).indexOf(o) > -1 ? ' checked' : '') + '> ' + esc(o) + '</label>';
      }).join('') + '</div></div>';
    }
    var max = kind.indexOf('t:') === 0 ? kind.slice(2) : '';
    if (kind === 'd') return '<div>' + lab + '<input class="input" id="' + id + '" type="date" data-any-date data-k="' + k + '" value="' + esc(val) + '"' + ar + '></div>';
    if (kind === 'mo') return '<div>' + lab + '<input class="input" id="' + id + '" type="month" data-any-date data-k="' + k + '" value="' + esc(val) + '"></div>';
    if (kind === 'y') return '<div>' + lab + '<input class="input" id="' + id + '" inputmode="numeric" maxlength="4" placeholder="2020" data-k="' + k + '" value="' + esc(val) + '"></div>';
    if (kind.indexOf('i:') === 0) return '<div>' + lab + '<input class="input" id="' + id + '" inputmode="numeric" maxlength="2" data-k="' + k + '" value="' + esc(val) + '"></div>';
    var wide = Number(max) > 100;
    return '<div' + (wide ? ' class="span-all"' : '') + '>' + lab + (Number(max) > 120
      ? '<textarea class="input" id="' + id + '" rows="2" maxlength="' + max + '" data-k="' + k + '"' + ar + '>' + esc(val) + '</textarea>'
      : '<input class="input" id="' + id + '" maxlength="' + max + '" data-k="' + k + '" value="' + esc(val) + '"' + ar +
        (/mobile|phone/.test(k) ? ' type="tel" inputmode="tel"' : /email/.test(k) ? ' type="email" inputmode="email"' : '') + '>') + '</div>';
  }
  function formBody(data) {
    return SECTIONS.map(function (s) {
      var fs = FIELDS.filter(function (f) { return f[0] === s[0]; });
      return '<section class="fsec" data-sec="' + s[0] + '"><h4 class="fsec-h">' + esc(s[1]) + '</h4><div class="row fgrid">' +
        fs.map(function (f) {
          var html = inputOf(f, data[f[1]]);
          return /^spouse_/.test(f[1]) ? html.replace(/^<div/, '<div data-spouse' + (data.marital === 'Married' ? '' : ' hidden')) : html;
        }).join('') + '</div></section>';
    }).join('') + (form.own ? '<section class="fsec"><h4 class="fsec-h">Declaration</h4>' +
      '<p class="prs-declare">I hereby certify that all information contained in this form is true, correct and complete to the best of my knowledge. ' +
      'I understand that any misrepresentation or omission of facts may be grounds for dismissal.</p>' +
      '<p class="prs-declare">I consent to the collection and processing of my personal data by ADSPACE PLT for the purposes of my employment, and I authorise the verification of any of the information above.</p>' +
      '<div class="row"><label class="tickline"><input type="checkbox" id="prsConsent" data-nodraft> I agree to the declaration and consent above.</label></div>' +
      '<div class="row"><div class="field"><label class="field-label" for="prsSign">Full name as signature</label>' +
      '<input class="input" id="prsSign" aria-required="true" maxlength="100" autocomplete="name" data-nodraft></div></div></section>' : '');
  }
  /* The form starts from the record, a field left empty taking what the
     colleague's Overview holds (the database's `prefill`: their sign-in
     email and namecard mobile; the user, 2026-11-24). Prefilled, not fixed:
     a saved value always wins, and nothing is kept until Save. */
  function startData(rec) {
    var out = {}, data = rec.data || {}, pre = rec.prefill || {};
    Object.keys(data).forEach(function (k) { out[k] = data[k]; });
    Object.keys(pre).forEach(function (k) {
      if (field(k) && (out[k] == null || out[k] === '') && pre[k]) out[k] = pre[k];
    });
    return out;
  }
  function openForm(rec, member, opener) {
    form.member = member; form.own = !member; form.rec = rec;
    $('prsSheetTitle').textContent = form.own ? 'Employee record' : 'Edit employee record';
    $('prsSave').textContent = form.own ? 'Submit' : 'Save';
    $('prsBody').innerHTML = formBody(startData(rec));
    msg('prsSheetMsg', '');
    if (form.own && rec.declared_name) $('prsSign').value = '';
    var mar = $('prs_marital');
    if (mar) mar.addEventListener('change', function () {
      Array.prototype.forEach.call($('prsBody').querySelectorAll('[data-spouse]'), function (el) { el.hidden = mar.value !== 'Married'; });
    });
    if (window.ADspaceForm && window.ADspaceForm.init) window.ADspaceForm.init($('prsBody'));
    window.ADspaceSheet.show($('prsSheet'), { opener: opener });
  }
  function collect() {
    var out = {};
    Array.prototype.forEach.call($('prsBody').querySelectorAll('[data-k]'), function (el) {
      var k = el.getAttribute('data-k'), f = field(k);
      if (!f) return;
      if (el.closest('[data-spouse][hidden]')) return;
      if (el.type === 'checkbox') { if (el.checked) (out[k] = out[k] || []).push(el.value); return; }
      var v = String(el.value || '').trim();
      if (!v) return;
      if (f[3] === 'b') { out[k] = v === 'yes'; return; }
      if (f[3].indexOf('i:') === 0) { out[k] = /^\d+$/.test(v) ? Number(v) : v; return; }
      out[k] = v;
    });
    return out;
  }
  function refuse(d) {
    var k = d.field || (d.missing && d.missing[0]);
    msg('prsSheetMsg', d.error === 'incomplete' ? 'Fill in ' + (d.missing || []).slice(0, 4).map(labelOf).join(', ') + ((d.missing || []).length > 4 ? ' and the other required fields.' : '.') :
      d.error === 'bad-field' && k ? 'Enter a valid ' + lowerFirst(labelOf(k)) + '.' : said(d));
    var el = k && $('prs_' + k);
    if (el) { if (window.ADspaceForm && window.ADspaceForm.reveal) window.ADspaceForm.reveal(el); el.focus(); }
  }
  function save() {
    var b = $('prsSave'), data = collect();
    if (form.own) {
      if (!$('prsConsent').checked) { msg('prsSheetMsg', SAID['no-consent']); $('prsConsent').focus(); return; }
      if ($('prsSign').value.trim().length < 2) { msg('prsSheetMsg', SAID['bad-name']); $('prsSign').focus(); return; }
    }
    b.disabled = true;
    var done = function (d) {
      b.disabled = false;
      if (d.error === 'stale' && d.record) { setRec(d.record); msg('prsSheetMsg', SAID.stale); return; }
      if (d.error) { refuse(d); return; }
      window.ADspaceSheet.clean(); window.ADspaceSheet.close();
      setRec(d);
      msg(form.own ? 'minePrsMsg' : 'prsMsg', form.own ? 'Submitted.' : 'Saved.', 'ok');
    };
    if (form.own) mineCall('personnel_save_mine', { p_data: data, p_consent: true, p_name: $('prsSign').value, p_expected: form.rec.updated_at || null }, done);
    else call('personnel_save', { p_member: form.member, p_data: data, p_expected: form.rec.updated_at || null }, done);
  }

  // ---- Employment terms --------------------------------------------------------------
  function openTerms(opener) {
    var rec = team.rec, m = team.m;
    var people = (team.people || []).filter(function (t) { return t.active && t.id !== m.id && !(bridge.isSystem && bridge.isSystem(t.id)); });
    window.ADspaceConfirm.ask({
      title: 'Employment terms', go: 'Save', wait: true, opener: opener,
      fields: [
        { name: 'join', label: 'Join date', type: 'date', value: rec.join_date || '', required: false, half: true },
        { name: 'probation', label: 'Probation (months)', type: 'number', min: '0', max: '12', value: rec.probation_months == null ? '' : String(rec.probation_months), required: false, half: true },
        { name: 'status', label: 'Employee status', choices: [['', 'Not set']].concat(STATUSES.map(function (s) { return [s, s]; })), value: rec.employee_status || '' },
        { name: 'type', label: 'Employee type', choices: [['', 'Not set']].concat(TYPES), value: rec.employee_type || '', seg: true },
        { name: 'end', label: 'End of contract', type: 'date', value: rec.contract_end || '', required: false, note: 'For a contract or an internship.' },
        { name: 'superior', label: 'Reports to', choices: [['', 'Not set']].concat(people.map(function (t) { return [t.id, (t.staff_code ? t.staff_code + ' · ' : '') + t.name]; })), value: rec.superior_id || '' }]
    }, function (v) {
      return new Promise(function (ok) {
        var type = v.type || (v.status ? TYPE_OF[v.status] : '') || null;
        call('personnel_terms_set', { p_member: m.id, p_join: v.join || null, p_status: v.status || null, p_type: type,
          p_probation: v.probation === '' || v.probation == null ? null : Number(v.probation), p_contract_end: v.end || null,
          p_superior: v.superior || null }, function (d) {
          if (d.error) { ok(said(d)); return; }
          setRec(d); msg('prsMsg', 'Saved.', 'ok'); ok('');
        });
      });
    });
  }

  // ---- The salary, behind a caution and the unlock (decision 10) ----------------------
  var P = function () { return window.ADspacePerf || {}; };
  /* The caution step, then the master code where no unlock stands. */
  function unlocked(then, opener) {
    window.ADspaceConfirm.ask({ title: 'Sensitive information follows', body: 'Proceed with caution.', go: 'Continue', opener: opener }, function () {
      var tok = P().token ? P().token() : null;
      if (tok) { then(tok); return; }
      askCode(then);
    });
  }
  function askCode(then) {
    window.ADspaceConfirm.ask({ title: 'Master code', body: 'Unlocks for 15 minutes.', go: 'Unlock', wait: true,
      fields: [{ name: 'code', label: 'Master code', type: 'password', required: true }] }, function (v) {
      return new Promise(function (ok) {
        call('personnel_unlock', { p_code: v.code }, function (d) {
          if (d.error) { ok(said(d)); return; }
          if (P().keepToken) P().keepToken(d.token);
          ok('');
          setTimeout(function () { then(d.token); }, 0);
        });
      });
    });
  }
  function relock(d, again) {
    if (d && (d.error === 'code-needed' || d.error === 'locked')) { if (P().keepToken) P().keepToken(null); askCode(again); return true; }
    return false;
  }
  function money(n) { return n == null ? '' : Number(n).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); }
  function salaryOpen(opener) {
    var m = team.m;
    if (!m) return;
    unlocked(function go(tok) {
      call('personnel_salary_get', { p_token: tok, p_member: m.id }, function (d) {
        if (relock(d, go)) return;
        if (d.error) { msg('prsMsg', said(d)); return; }
        window.ADspaceConfirm.ask({
          title: 'Salary', body: m.name, go: 'Save', wait: true, trace: true,
          fields: [
            { name: 'probation', label: 'Salary during probation (RM)', type: 'number', min: '0', value: money(d.probation).replace(/,/g, ''), required: false },
            { name: 'confirmed', label: 'Salary after probation (RM)', type: 'number', min: '0', value: money(d.confirmed).replace(/,/g, ''), required: false }],
          check: function (v) {
            var bad = ['probation', 'confirmed'].filter(function (k) { return v[k] !== '' && !/^\d{1,7}(\.\d{1,2})?$/.test(String(v[k]).trim()); });
            return bad.length ? 'Enter an amount in RM, to the cent.' : '';
          }
        }, function (v) {
          return new Promise(function (ok) {
            call('personnel_salary_set', { p_token: tok, p_member: m.id,
              p_probation: v.probation === '' ? null : Number(v.probation), p_confirmed: v.confirmed === '' ? null : Number(v.confirmed) }, function (x) {
              if (x.error) { ok(said(x)); return; }
              team.rec.salary_set = x.probation != null || x.confirmed != null; paintTeam(); msg('prsMsg', 'Saved.', 'ok'); ok('');
            });
          });
        });
      });
    }, opener);
  }

  // ---- Files: NRIC front and back, photograph (S3 private/) ---------------------------
  /* A picture is drawn down to 1600px as a JPEG before it goes. */
  function shrink(file) {
    if (!/^image\/(jpeg|png)$/.test(file.type)) return Promise.resolve({ blob: file, ext: 'pdf' });
    return new Promise(function (ok, no) {
      var img = new Image(), url = URL.createObjectURL(file);
      img.onload = function () {
        var s = Math.min(1, 1600 / Math.max(img.width, img.height)), c = document.createElement('canvas');
        c.width = Math.round(img.width * s); c.height = Math.round(img.height * s);
        c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
        URL.revokeObjectURL(url);
        c.toBlob(function (b) { if (b) ok({ blob: b, ext: 'jpg' }); else no(new Error('The picture could not be read. Choose a JPEG or PNG file.')); }, 'image/jpeg', 0.88);
      };
      img.onerror = function () { URL.revokeObjectURL(url); no(new Error('The picture could not be read. Choose a JPEG or PNG file.')); };
      img.src = url;
    });
  }
  function upload(member, kind, file) {
    var cfg = window.ADSPACE_CONFIG || {};
    return shrink(file).then(function (x) {
      if (x.blob.size > 10 * 1024 * 1024) throw new Error('Choose a file of 10 MB at most.');
      return db.functions.invoke((cfg.s3 && cfg.s3.functionName) || 'sign-upload', {
        body: { purpose: 'personnel', memberId: member || null, kind: kind, ext: x.ext, size: x.blob.size }
      }).then(function (r) {
        if (!r.error && r.data && r.data.uploadUrl) return { r: r, blob: x.blob };
        return API.fnRefusal(r).then(function (code) { throw new Error(code === 'not_allowed' ? SAID.denied : 'The file could not be saved. Try again.'); });
      });
    }).then(function (o) {
      return fetch(o.r.data.uploadUrl, { method: 'PUT', headers: { 'Content-Type': o.r.data.contentType }, body: o.blob })
        .then(function (res) { if (!res.ok) throw new Error('The file could not be saved. Try again.'); return o.r.data.key; });
    }).then(function (key) {
      return new Promise(function (ok, no) {
        (member ? call : mineCall)('personnel_file_set', { p_member: member || null, p_kind: kind, p_key: key }, function (d) {
          if (d.error) no(new Error(said(d))); else ok(d);
        });
      });
    });
  }
  function view(member, kind) {
    /* Through ADspaceDocs' viewer over the page, never a tab of its own:
       the viewer carries the reader's trace (js/trace.js), which a tab
       holding the bare picture cannot (2026-11-24). */
    var Docs = window.ADspaceDocs;
    var tab = Docs.previewTab(false, { trace: true });
    return db.functions.invoke('sign-download', { body: { personnel: { member: member || null, kind: kind } } }).then(function (r) {
      if (!r || r.error) throw new Error('The file could not be opened. Try again.');
      return window.ADspaceAPI.fileOf(r.data).then(function (f) {
        if (!f) throw new Error('The file could not be opened. Try again.');
        var ext = /pdf/.test(f.type) ? 'pdf' : /png/.test(f.type) ? 'png' : 'jpg';
        return Docs.save(f, kind + '.' + ext, tab);
      });
    }).catch(function (e) { if (tab && tab.close) tab.close(); throw e; });
  }
  function wireFiles(box, member) {
    var line = box.querySelector('[data-fmsg]');
    Array.prototype.forEach.call(box.querySelectorAll('.prs-file'), function (row) {
      var kind = row.getAttribute('data-file');
      var pick = row.querySelector('input[data-f="pick"]');
      if (pick) pick.addEventListener('change', function () {
        var f = pick.files && pick.files[0];
        if (!f) return;
        msg(line, 'Saving…', 'ok');
        upload(member, kind, f).then(function (d) { setRec(d); }).catch(function (e) { msg(line, (e && e.message) || 'Not saved.'); });
      });
      var v = row.querySelector('[data-f="view"]');
      if (v) v.addEventListener('click', function () { view(member, kind).catch(function (e) { msg(line, e.message); }); });
      var mb = row.querySelector('[data-f="menu"]'), mn = row.querySelector('[data-menu]');
      if (mb) {
        mb.addEventListener('click', function (e) {
          e.stopPropagation();
          var open = mn.hidden;
          mn.hidden = !open; mb.setAttribute('aria-expanded', String(open));
          if (open && window.ADspaceMenu) window.ADspaceMenu.place(mb, mn);
        });
        document.addEventListener('click', function (e) { if (!row.contains(e.target)) { mn.hidden = true; mb.setAttribute('aria-expanded', 'false'); } });
      }
      var rm = row.querySelector('[data-f="remove"]');
      if (rm) rm.addEventListener('click', function () {
        mn.hidden = true; mb.setAttribute('aria-expanded', 'false');
        window.ADspaceConfirm.ask({ title: 'Delete file?', body: 'The file will be deleted from this employee record. This cannot be undone.', go: 'Delete', tone: 'danger', wait: true, opener: mb }, function () {
          return new Promise(function (ok) {
            (member ? call : mineCall)('personnel_file_remove', { p_member: member || null, p_kind: kind }, function (d) {
              if (d.error) { ok(said(d)); return; }
              ok(''); setRec(d);
            });
          });
        });
      });
    });
  }

  // ---- My records: the colleague's own ------------------------------------------------
  var mine = { rec: null };
  function enterMine() {
    var box = $('minePrsBox');
    if (!box) return;
    if (!mine.rec) UI.skeleton(box, 4);
    mineCall('personnel_mine', {}, function (d) {
      if (d.error) { if (d.error !== 'code-needed') UI.failLine(box, 'Your employee record', said(d), enterMine); return; }
      mine.rec = d;
      paintMine();
    });
  }
  function paintMine() {
    var box = $('minePrsBox'), rec = mine.rec;
    if (!box || !rec) return;
    hideAll();
    var act = '<button class="btn btn-sm' + (rec.declared_at ? '' : ' btn-primary') + '" type="button" data-p="edit">' +
      (rec.declared_at ? PEN + 'Edit' : 'Fill in') + '</button>';
    box.innerHTML = '<div class="panel mrec-card prs-card" data-trace><div class="readgroups">' +
      statusGroup(rec, false, act) +
      (rec.join_date || rec.employee_status ? termsGroup(rec, false) : '') +
      filesGroup(rec, true) + readSections(rec) + '</div></div>';
    var e = box.querySelector('[data-p="edit"]');
    e.addEventListener('click', function () { openForm(rec, null, e); });
    wireFiles(box, null);
    wireEyes(box, rec, null, 'minePrsMsg');
  }

  // ---- Download for AutoCount (decision 9) -------------------------------------------
  var HEAD = ["Code", "Name", "Job Title", "Gender", "Marital Status", "IC Number", "Passport Number", "Passport Expiry Date", "Immigration Number", "Is Disable", "Address", "PostalCode", "City", "State", "Residence Country", "Phone Number", "Mobile Number", "Email Address", "Join Date", "Confirm Date", "Resign Date", "Payment By", "Birth Date", "EA Serial Number", "Tax Number", "Tax Branch", "SOCSO Number", "SOCSO Category", "EPF Number", "NK", "EPF Initial", "Spouse Name", "Is Spouse Working", "Spouse Address", "Spouse Phone Number", "Spouse Mobile Number", "Spouse Tax Number", "Spouse IC Number", "Is Spouse Disable", "Deductible Child Number", "Deductible Child Relief Point", "Note", "Department Code", "Race Code", "Employee Type Code", "Branch Code", "Project Code", "Overtime Code", "Calendar Code", "Levy Code", "Wages Type", "Basic Rate", "Pay Frequency", "Pay HRDF", "Zakat Number", "Tabung Haji Number", "ASN Number", "Superior", "Emergency Name", "Emergency Phone Number", "Emergency Relationship", "Education", "Working Experience", "User Email", "EPF Code", "EPF Borne by Employer", "SOCSO Borne by Employer", "SKBBK Exempted", "EIS Borne by Employer", "Is Tax By Employer", "Claim Employee's SOCSO & EIS Tax Relief", "Director Fee", "ASN Amount", "Tabung Haji Amount", "Zakat Amount", "Is Company Partner", "Pay EIS", "Is Foreigner", "Entitlement Group", "Tax Status", "SOCSO Employement Status", "Religion", "Working Permit Expiry Date", "EClaim", "ELeave", "Leave Requires Replacement", "Nationality", "Old IC Number", "Time Attendance", "Face Recognition", "Default Rule", "Is Active", "Employee Status", "End Of Contract", "Retirement Date"];
  var BANK_HEAD = ['Employee Code', 'Bank Id', 'Account No.', 'Beneficiary Name', 'State', 'Salary Percent', 'Is Main Bank', 'IC Number'];
  /* AutoCount's limits a column (row 1 of the template). */
  var MAX = { Code: 20, Name: 60, 'Job Title': 50, 'IC Number': 20, 'Passport Number': 15, 'Immigration Number': 25, Address: 250,
    PostalCode: 5, City: 50, State: 50, 'Residence Country': 200, 'Mobile Number': 25, 'Email Address': 256, 'Tax Number': 20,
    'SOCSO Number': 12, 'EPF Number': 9, 'Spouse Name': 60, 'Spouse Mobile Number': 25, 'Spouse Tax Number': 20, 'Spouse IC Number': 20,
    'Department Code': 20, 'Race Code': 50, Superior: 60, 'Emergency Name': 60, 'Emergency Phone Number': 25,
    'Emergency Relationship': 50, Education: 150, 'Working Experience': 150, 'User Email': 250, 'Old IC Number': 20 };
  function dmy(s) { return /^\d{4}-\d{2}-\d{2}/.test(s || '') ? s.slice(8, 10) + '/' + s.slice(5, 7) + '/' + s.slice(0, 4) : ''; }
  function yes(v) { return v === true ? '1' : v === false ? '0' : ''; }
  function rowOf(x, set) {
    var d = x.data || {}, married = d.marital === 'Married';
    var edu = ['university', 'professional', 'college', 'secondary', 'primary'].map(function (k) {
      return [d['edu_' + k + '_qual'], d['edu_' + k + '_school']].filter(Boolean).join(', ');
    }).filter(Boolean)[0] || '';
    var job = [d.job_1_position, d.job_1_company].filter(Boolean).join(', ');
    var foreign = d.nationality && d.nationality !== 'Malaysia';
    var v = {
      Code: x.code, Name: (d.full_name || x.name || '').toUpperCase(), 'Job Title': x.designation, Gender: d.gender,
      'Marital Status': d.marital, 'IC Number': d.nric, 'Passport Number': d.passport,
      'Passport Expiry Date': dmy(d.passport_expiry), 'Immigration Number': d.immigration_no, 'Is Disable': yes(d.disabled) || '0',
      Address: [d.address1, d.address2].filter(Boolean).join(', '), PostalCode: d.postcode, City: d.city, State: d.state,
      'Residence Country': d.country, 'Mobile Number': d.mobile, 'Email Address': d.email,
      'Join Date': dmy(x.join_date), 'Confirm Date': dmy(x.confirm_date), 'Payment By': set.payment_by, 'Birth Date': dmy(d.birth_date),
      'Tax Number': d.tax_no, 'SOCSO Number': d.socso_no, 'SOCSO Category': set.socso_category, 'EPF Number': d.epf_no,
      'Spouse Name': married ? d.spouse_name : '', 'Is Spouse Working': married ? yes(d.spouse_working) : '',
      'Spouse Mobile Number': married ? d.spouse_phone : '', 'Spouse Tax Number': married ? d.spouse_tax : '',
      'Spouse IC Number': married ? d.spouse_ic : '', 'Is Spouse Disable': married ? yes(d.spouse_disabled) : '',
      'Deductible Child Number': d.children_relief == null ? '' : String(d.children_relief),
      'Department Code': x.department_code, 'Race Code': d.race, 'Employee Type Code': x.employee_type, 'Branch Code': set.branch,
      'Calendar Code': set.calendar, 'Wages Type': set.wages_type, 'Basic Rate': x.basic_rate == null ? '' : String(x.basic_rate),
      'Pay Frequency': set.pay_frequency, 'Pay HRDF': set.pay_hrdf, Superior: x.superior_code,
      'Emergency Name': d.kin_name, 'Emergency Phone Number': d.kin_mobile, 'Emergency Relationship': d.kin_relation,
      Education: edu, 'Working Experience': job, 'User Email': x.email, 'EPF Code': set.epf_code,
      'EPF Borne by Employer': set.epf_borne, 'SOCSO Borne by Employer': set.socso_borne, 'SKBBK Exempted': set.skbbk_exempted,
      'EIS Borne by Employer': set.eis_borne, 'Is Tax By Employer': set.tax_by_employer,
      "Claim Employee's SOCSO & EIS Tax Relief": set.socso_eis_relief, 'Is Company Partner': '0', 'Pay EIS': set.pay_eis,
      'Is Foreigner': foreign ? '1' : '0', 'Entitlement Group': set.entitlement_group, 'Tax Status': set.tax_status,
      'SOCSO Employement Status': set.socso_status, Religion: d.religion, 'Working Permit Expiry Date': dmy(d.permit_expiry),
      EClaim: set.eclaim, ELeave: set.eleave, 'Leave Requires Replacement': '0', Nationality: d.nationality,
      'Old IC Number': d.old_ic, 'Time Attendance': '0', 'Face Recognition': '0', 'Is Active': '1',
      'Employee Status': x.employee_status, 'End Of Contract': dmy(x.contract_end)
    };
    return v;
  }
  /* What AutoCount would refuse, a line a colleague, before anything is made. */
  function problems(x, v) {
    var out = [], who = (x.code || 'No Employee ID') + ' · ' + x.name;
    var need = { Code: 'Employee ID', Name: 'Name', Gender: 'Gender', 'Marital Status': 'Marital status', 'Join Date': 'Join date',
      'Birth Date': 'Date of birth', 'Department Code': 'Department code', 'Employee Type Code': 'Employee type',
      'Employee Status': 'Employee status', 'Basic Rate': 'Salary', 'Residence Country': 'Country', Nationality: 'Nationality' };
    Object.keys(need).forEach(function (h) { if (!v[h]) out.push(who + ': ' + need[h] + ' is not set.'); });
    if (!v['IC Number'] && !v['Passport Number']) out.push(who + ': NRIC Number or Passport Number is not set.');
    Object.keys(MAX).forEach(function (h) { if (v[h] && String(v[h]).length > MAX[h]) out.push(who + ': shorten ' + h + ' to ' + MAX[h] + ' characters.'); });
    if (v.Nationality && COUNTRIES.indexOf(v.Nationality) < 0) out.push(who + ': choose a nationality from the list.');
    if (v['Residence Country'] && COUNTRIES.indexOf(v['Residence Country']) < 0) out.push(who + ': choose a country from the list.');
    if (v.PostalCode && !/^\d{5}$/.test(v.PostalCode) && v['Residence Country'] === 'Malaysia') out.push(who + ': enter a 5-digit postal code.');
    var b = x.data || {};
    if (!b.bank || !b.bank_account || !b.bank_holder) out.push(who + ': complete the bank details.');
    else if (BANKS.indexOf(b.bank) < 0) out.push(who + ': choose a bank from the list.');
    return out;
  }
  function exportAC(opener) {
    unlocked(function go(tok) {
      call('personnel_export', { p_token: tok }, function (d) {
        if (relock(d, go)) return;
        if (d.error) { teamSay(said(d)); return; }
        var set = d.settings || {}, rows = (d.rows || []).filter(function (x) { return !(bridge.isSystem && bridge.isSystem(x.member)); });
        var issues = [], emp = [], bank = [];
        rows.forEach(function (x) {
          var v = rowOf(x, set), p = problems(x, v);
          issues = issues.concat(p);
          emp.push(HEAD.map(function (h) { return v[h] == null ? '' : String(v[h]); }));
          var b = x.data || {};
          bank.push([x.code, b.bank, b.bank_account, (b.bank_holder || '').toUpperCase(), b.state, '100', '1', b.nric || b.passport]);
        });
        if (!rows.length) issues.push('No active colleague to download.');
        if (issues.length) {
          window.ADspaceConfirm.ask({ title: 'Not downloaded', go: 'Close', cancel: false,
            body: issues.slice(0, 10).join('\n') + (issues.length > 10 ? '\nAnd ' + (issues.length - 10) + ' more.' : '') }, function () {});
          return;
        }
        fetch('/admin/hr/achrms-template.xlsx?v=20261116').then(function (r) {
          if (!r.ok) throw new Error('template');
          return r.arrayBuffer();
        }).then(function (buf) {
          return window.ADspaceXlsx.fill(buf, { Employee: emp, EmployeeBank: bank });
        }).then(function (blob) {
          var day = window.ADspaceClock.today().replace(/-/g, '');
          var a = document.createElement('a'), url = URL.createObjectURL(blob);
          a.href = url; a.download = 'AutoCount HRMS Employees ' + day + '.xlsx';
          document.body.appendChild(a); a.click(); a.remove();
          setTimeout(function () { URL.revokeObjectURL(url); }, 60000);
          teamSay('Downloaded.', 'ok');
        }).catch(function () { teamSay('The file could not be made. Refresh the page and try again.'); });
      });
    }, opener);
  }
  function teamSay(text, kind) { msg('teamMsg', text, kind); }

  // ---- Settings: AutoCount HRMS defaults ---------------------------------------------
  var LABEL = { payment_by: 'Payment By', wages_type: 'Wages Type', pay_frequency: 'Pay Frequency', epf_code: 'EPF Code',
    socso_category: 'SOCSO Category', tax_status: 'Tax Status', socso_status: 'SOCSO Employment Status', entitlement_group: 'Entitlement Group',
    calendar: 'Calendar', branch: 'Branch', eclaim: 'EClaim', eleave: 'ELeave', pay_eis: 'Pay EIS', pay_hrdf: 'Pay HRDF',
    epf_borne: 'EPF borne by employer', socso_borne: 'SOCSO borne by employer', eis_borne: 'EIS borne by employer',
    tax_by_employer: 'Tax borne by employer', socso_eis_relief: 'Claim SOCSO and EIS tax relief', skbbk_exempted: 'SKBBK exempted' };
  var ORDER = ['branch', 'calendar', 'entitlement_group', 'payment_by', 'wages_type', 'pay_frequency', 'epf_code', 'socso_category',
    'socso_status', 'tax_status', 'pay_eis', 'pay_hrdf', 'eclaim', 'eleave', 'epf_borne', 'socso_borne', 'eis_borne',
    'tax_by_employer', 'socso_eis_relief', 'skbbk_exempted'];
  function settingsLine() {
    return new Promise(function (ok, no) {
      call('personnel_settings_get', {}, function (d) {
        if (d.error) { no(new Error(said(d))); return; }
        var v = d.values || {};
        ok(['Branch ' + v.branch, 'EPF ' + v.epf_code, v.tax_status].filter(Boolean).join(' · '));
      });
    });
  }
  function openSettings(opener) {
    call('personnel_settings_get', {}, function (d) {
      if (d.error) { window.ADspaceConfirm.ask({ title: 'AutoCount HRMS', body: said(d), go: 'Close', cancel: false }, function () {}); return; }
      var v = d.values || {}, spec = d.spec || {};
      window.ADspaceConfirm.ask({
        title: 'AutoCount HRMS', go: 'Save', wait: true, opener: opener,
        fields: ORDER.map(function (k, i) {
          var list = String(spec[k] || '*');
          var f = { name: k, label: LABEL[k], value: v[k] || '', head: i === 0 ? 'Company' : i === 3 ? 'Pay' : i === 10 ? 'Switches' : undefined };
          if (list === '0|1') { f.choices = [['1', 'Yes'], ['0', 'No']]; f.seg = true; f.half = true; }
          else if (list !== '*') f.choices = list.split('|').map(function (o) { return [o, o]; });
          else { f.required = true; f.third = true; }
          return f;
        })
      }, function (vals) {
        return new Promise(function (ok) {
          call('personnel_settings_set', { p_values: vals }, function (x) {
            if (x.error) { ok(said(x)); return; }
            ok('');
            if (window.ADspaceSettings && window.ADspaceSettings.refresh) window.ADspaceSettings.refresh('autocount');
          });
        });
      });
    });
  }

  // ---- Wiring ---------------------------------------------------------------------------
  if ($('prsSheet')) {
    $('prsClose').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('prsCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('prsSave').addEventListener('click', save);
  }

  window.ADspacePersonnel = {
    paneTeam: paneTeam,
    enterMine: enterMine,
    exportAC: exportAC,
    openSettings: openSettings,
    settingsLine: settingsLine,
    /* The bell's masked probation notice: the colleague's tab, the caution and the unlock. */
    probation: function (member) { team.probation = member; },
    FIELDS: FIELDS,
    _rowOf: rowOf, _problems: problems, HEAD: HEAD
  };
})();
