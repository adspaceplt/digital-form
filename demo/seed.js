/* Sample data for the demo (2026-10-27): a made-up agency, its team and its
   clients, built afresh on every load so it is always current. Nothing here
   is a real business, person or figure. Read by demo/engine.js. */
(function () {
  'use strict';
  window.__demoSeed = function () {
  /* The workflows, holidays, tax codes, departments and document types the
     portal ships with. */
  var S = {"tax_codes":[{"code":"SV8","name":"Service tax 8%","rate":8,"active":true,"bukku_id":"1"},{"code":"SVE","name":"Exempt","rate":0,"active":true,"bukku_id":"2"},{"code":"SV6","name":"Service tax 6%","rate":6,"active":false,"bukku_id":"3"}],"departments":[{"key":"creative","name":"Creative","active":true,"in_prize":true,"position":1,"criteria":["On-time creative delivery","Creative quality and revision","Client performance support","Asset organisation","Cross-functional responsiveness"]},{"key":"marketing","name":"Marketing","active":true,"in_prize":true,"position":2,"criteria":["Client account health","Campaign planning and execution","Posting and servicing accuracy","Reporting and proactive improvement","Brief and handover quality"]}],"public_holidays":[{"day":"2026-02-01","name":"Thaipusam"},{"day":"2026-02-02","name":"Thaipusam (replacement holiday)"},{"day":"2026-02-17","name":"Chinese New Year"},{"day":"2026-02-18","name":"Chinese New Year (second day)"},{"day":"2026-02-19","name":"Awal Ramadan"},{"day":"2026-03-20","name":"Hari Raya Aidilfitri (additional holiday)"},{"day":"2026-03-21","name":"Hari Raya Aidilfitri"},{"day":"2026-03-22","name":"Hari Raya Aidilfitri (second day)"},{"day":"2026-03-23","name":"Birthday of the Sultan of Johor"},{"day":"2026-03-24","name":"Hari Raya Aidilfitri (replacement holiday)"},{"day":"2026-05-01","name":"Labour Day"},{"day":"2026-05-27","name":"Hari Raya Haji"},{"day":"2026-05-31","name":"Wesak Day"},{"day":"2026-06-01","name":"Birthday of the Yang di-Pertuan Agong"},{"day":"2026-06-02","name":"Wesak Day (replacement holiday)"},{"day":"2026-06-17","name":"Awal Muharram"},{"day":"2026-07-21","name":"Hari Hol Almarhum Sultan Iskandar"},{"day":"2026-08-25","name":"Maulidur Rasul"},{"day":"2026-08-31","name":"National Day"},{"day":"2026-09-16","name":"Malaysia Day"},{"day":"2026-11-08","name":"Deepavali"},{"day":"2026-11-09","name":"Deepavali (replacement holiday)"},{"day":"2026-12-25","name":"Christmas Day"},{"day":"2027-01-22","name":"Thaipusam"},{"day":"2027-02-06","name":"Chinese New Year"},{"day":"2027-02-07","name":"Chinese New Year (second day)"},{"day":"2027-02-08","name":"Awal Ramadan; Chinese New Year (replacement holiday)"},{"day":"2027-02-09","name":"Awal Ramadan (replacement holiday)"},{"day":"2027-03-10","name":"Hari Raya Aidilfitri"},{"day":"2027-03-11","name":"Hari Raya Aidilfitri (second day)"},{"day":"2027-03-23","name":"Birthday of the Sultan of Johor"},{"day":"2027-05-01","name":"Labour Day"},{"day":"2027-05-17","name":"Hari Raya Haji"},{"day":"2027-05-20","name":"Wesak Day"},{"day":"2027-06-06","name":"Awal Muharram"},{"day":"2027-06-07","name":"Birthday of the Yang di-Pertuan Agong"},{"day":"2027-06-08","name":"Awal Muharram (replacement holiday)"},{"day":"2027-07-11","name":"Hari Hol Almarhum Sultan Iskandar"},{"day":"2027-07-12","name":"Hari Hol Almarhum Sultan Iskandar (replacement holiday)"},{"day":"2027-08-15","name":"Maulidur Rasul"},{"day":"2027-08-16","name":"Maulidur Rasul (replacement holiday)"},{"day":"2027-08-31","name":"National Day"},{"day":"2027-09-16","name":"Malaysia Day"},{"day":"2027-10-28","name":"Deepavali"},{"day":"2027-12-25","name":"Christmas Day"}],"doc_types":[{"id":"dt-cover","code":"QT","name":"Quotation Cover","family":"quote_cover","signed":false,"languages":["en","zh","ms"],"title":"QUOTATION","salutation":"Dear Sir/Madam,","body_en":"We are pleased to enclose our quotation for your kind consideration.","body_zh":"随函附上报价单，敬请过目。","body_ms":"","position":10,"active":true},{"id":"dt-thanks","code":"SC","name":"Thank You Letter","family":"client","signed":true,"languages":["en"],"title":"THANK YOU","salutation":"Dear {first name},","body_en":"Thank you for your continued support of SAMPLE STUDIO.","position":20,"active":true},{"id":"dt-letter","code":"GL","name":"Letter to Client","family":"client","signed":true,"languages":["en"],"title":"LETTER","salutation":"Dear {first name},","body_en":"We write regarding your account with us.","position":30,"active":true},{"id":"supplier_letter","code":"GL","name":"Letter to Supplier","family":"supplier","signed":true,"languages":["en"],"title":"","salutation":"Dear Sir/Madam,","body_en":"We write regarding our engagement with {supplier}.","position":60,"active":false},{"id":"supplier_sca","code":"SCA","name":"Supplier Service Agreement","family":"supplier","signed":true,"languages":["en"],"title":"Service Agreement","salutation":"","closing":"","position":59,"active":true,"body_en":"# Parties\n\nThis Advertising Management Services Agreement is made on the Agreement Date stated in Schedule A between SAMPLE STUDIO and the Supplier.\n\n# Services\n\n1. The Supplier will provide the ads management services set out in Schedule A.\n\n1. During the Term the Supplier will not:\n\na. use Confidential Information for any other client; or\n\na. run ads for a direct competitor of an assigned Client.\n\n# Governing Law\n\nThis Agreement is governed by the laws of Malaysia.","schedule":{"platforms":"Meta","tasks":"Campaign setup, audience building, ad copy, A/B testing, budget pacing, daily monitoring, optimisation","reporting":"Weekly snapshots to the Company and monthly reporting to the Company's clients","response":"Within 4 working hours on working days","spend_limit":"Changes above 40% per day need written approval","tolerance":"Actual monthly spend within ±10% of the approved budget","notes":"The Company may add, remove or change an account or its Approved Budget by sharing a new copy of this Schedule B.\n\nA blank End date means the account is ongoing."}},{"id":"dt-employ","code":"E","name":"Confirmation of Employment","family":"hr","signed":true,"languages":["en"],"title":"CONFIRMATION OF EMPLOYMENT","salutation":"Dear {first name},","body_en":"This is to confirm that you are employed by SAMPLE STUDIO as {role}.","position":40,"active":true},{"id":"dt-hr","code":"GL","name":"HR Letter","family":"hr","signed":true,"languages":["en"],"title":"LETTER","salutation":"Dear {first name},","body_en":"We write regarding your employment with SAMPLE STUDIO.","position":50,"active":true}],"ops_workflows":[{"id":"wf1","key":"general","name":"General","position":0,"active":false},{"id":"wf2","key":"video","name":"Video","position":1,"active":false},{"id":"wf3","key":"content","name":"Content deliverable","position":2,"active":true},{"id":"wf4","key":"task","name":"Everyday task","position":3,"active":true}],"ops_workflow_stages":[{"id":"c1s","workflow_id":"wf3","key":"planning","label":"Planning","stage_group":"intake","position":16,"is_active_work":false,"is_waiting":false,"is_review":false,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["ready","on_hold","cancelled"],"retired":true},{"id":"c2s","workflow_id":"wf3","key":"meeting_scheduled","label":"Content meeting scheduled","stage_group":"intake","position":17,"is_active_work":false,"is_waiting":true,"is_review":false,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["ready","on_hold","cancelled"],"retired":true},{"id":"c3s","workflow_id":"wf3","key":"ready","label":"Ready to start","stage_group":"ready","position":1,"is_active_work":false,"is_waiting":false,"is_review":false,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["in_production","blocked","on_hold","cancelled"],"retired":false},{"id":"c4s","workflow_id":"wf3","key":"in_production","label":"In progress","stage_group":"active","position":2,"is_active_work":true,"is_waiting":false,"is_review":false,"is_terminal":false,"wip_guidance":6,"next_stage_keys":["internal_review","ready","blocked","on_hold","cancelled"],"retired":false},{"id":"c5s","workflow_id":"wf3","key":"internal_review","label":"AQC review","stage_group":"internal_review","position":3,"is_active_work":false,"is_waiting":true,"is_review":true,"is_terminal":false,"wip_guidance":8,"next_stage_keys":["client_review","revision_internal","in_production","blocked","on_hold","cancelled"],"retired":false},{"id":"c6s","workflow_id":"wf3","key":"client_review","label":"Client review","stage_group":"client_review","position":5,"is_active_work":false,"is_waiting":true,"is_review":true,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["approved","revision_client","blocked","on_hold","cancelled"],"retired":false},{"id":"c7s","workflow_id":"wf3","key":"changes_requested","label":"Changes requested","stage_group":"revision","position":18,"is_active_work":true,"is_waiting":false,"is_review":false,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["in_production","internal_review","client_review","approved","blocked"],"retired":true},{"id":"c8s","workflow_id":"wf3","key":"approved","label":"Approved","stage_group":"approved","position":7,"is_active_work":false,"is_waiting":false,"is_review":false,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["scheduled","live","revision_client","on_hold","cancelled"],"retired":false},{"id":"c9s","workflow_id":"wf3","key":"published","label":"Published","stage_group":"done","position":19,"is_active_work":false,"is_waiting":false,"is_review":false,"is_terminal":true,"wip_guidance":null,"next_stage_keys":["changes_requested"],"retired":true},{"id":"c10s","workflow_id":"wf3","key":"blocked","label":"Blocked","stage_group":"blocked","position":13,"is_active_work":false,"is_waiting":true,"is_review":false,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["ready","in_production","internal_review","revision_internal","client_review","revision_client","scheduled","cancelled"],"retired":false},{"id":"c11s","workflow_id":"wf3","key":"on_hold","label":"On hold","stage_group":"waiting","position":12,"is_active_work":false,"is_waiting":true,"is_review":false,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["ready","in_production","internal_review","revision_internal","client_review","revision_client","scheduled","cancelled","approved"],"retired":false},{"id":"c12s","workflow_id":"wf3","key":"cancelled","label":"Cancelled","stage_group":"cancelled","position":14,"is_active_work":false,"is_waiting":false,"is_review":false,"is_terminal":true,"wip_guidance":null,"next_stage_keys":["ready","in_production","internal_review","revision_internal","client_review","revision_client","approved","scheduled"],"retired":false},{"id":"c13s","workflow_id":"wf3","key":"revision_internal","label":"Revision (Internal)","stage_group":"revision","position":4,"is_active_work":true,"is_waiting":false,"is_review":false,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["internal_review","blocked","on_hold","cancelled"],"retired":false},{"id":"c14s","workflow_id":"wf3","key":"revision_client","label":"Revision (Client)","stage_group":"revision","position":6,"is_active_work":true,"is_waiting":false,"is_review":false,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["client_review","internal_review","blocked","on_hold","cancelled"],"retired":false},{"id":"c15s","workflow_id":"wf3","key":"scheduled","label":"Scheduled","stage_group":"scheduled","position":8,"is_active_work":false,"is_waiting":true,"is_review":false,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["live","revision_client","on_hold","cancelled"],"retired":false},{"id":"c16s","workflow_id":"wf3","key":"live","label":"Live","stage_group":"live","position":9,"is_active_work":false,"is_waiting":true,"is_review":false,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["performance_review","taken_down"],"retired":false},{"id":"c17s","workflow_id":"wf3","key":"performance_review","label":"Performance review","stage_group":"performance","position":10,"is_active_work":false,"is_waiting":false,"is_review":true,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["completed","taken_down","live"],"retired":false},{"id":"c18s","workflow_id":"wf3","key":"taken_down","label":"Taken down","stage_group":"taken_down","position":15,"is_active_work":false,"is_waiting":false,"is_review":false,"is_terminal":true,"wip_guidance":null,"next_stage_keys":["live"],"retired":false},{"id":"c19s","workflow_id":"wf3","key":"completed","label":"Completed","stage_group":"done","position":11,"is_active_work":false,"is_waiting":false,"is_review":false,"is_terminal":true,"wip_guidance":null,"next_stage_keys":["performance_review"],"retired":false},{"id":"e1s","workflow_id":"wf4","key":"todo","label":"To do","stage_group":"intake","position":1,"is_active_work":false,"is_waiting":false,"is_review":false,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["doing","waiting","review","complete","cancelled"]},{"id":"e2s","workflow_id":"wf4","key":"doing","label":"In progress","stage_group":"active","position":2,"is_active_work":true,"is_waiting":false,"is_review":false,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["todo","waiting","review","complete","cancelled"]},{"id":"e3s","workflow_id":"wf4","key":"waiting","label":"Waiting","stage_group":"waiting","position":3,"is_active_work":false,"is_waiting":true,"is_review":false,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["todo","doing","review","complete","cancelled"]},{"id":"e4s","workflow_id":"wf4","key":"review","label":"Review","stage_group":"internal_review","position":4,"is_active_work":false,"is_waiting":true,"is_review":true,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["todo","doing","waiting","complete","cancelled"]},{"id":"e5s","workflow_id":"wf4","key":"complete","label":"Done","stage_group":"done","position":5,"is_active_work":false,"is_waiting":false,"is_review":false,"is_terminal":true,"wip_guidance":null,"next_stage_keys":["todo","doing"]},{"id":"e6s","workflow_id":"wf4","key":"cancelled","label":"Cancelled","stage_group":"cancelled","position":6,"is_active_work":false,"is_waiting":false,"is_review":false,"is_terminal":true,"wip_guidance":null,"next_stage_keys":["todo"]},{"id":"s1","workflow_id":"wf1","key":"intake","label":"Intake","stage_group":"intake","position":0,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["ready","cancelled","kiv"]},{"id":"s2","workflow_id":"wf1","key":"ready","label":"Ready","stage_group":"ready","position":1,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["in_progress","intake","blocked","cancelled"]},{"id":"s3","workflow_id":"wf1","key":"in_progress","label":"In progress","stage_group":"active","position":2,"is_terminal":false,"wip_guidance":5,"next_stage_keys":["internal_review","ready","blocked","waiting","cancelled"]},{"id":"s4","workflow_id":"wf1","key":"internal_review","label":"Internal review","stage_group":"internal_review","position":3,"is_terminal":false,"wip_guidance":3,"next_stage_keys":["client_review","in_progress","blocked","cancelled"]},{"id":"s5","workflow_id":"wf1","key":"client_review","label":"Client review","stage_group":"client_review","position":4,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["approved","in_progress","blocked","cancelled"]},{"id":"s6","workflow_id":"wf1","key":"approved","label":"Approved","stage_group":"approved","position":5,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["delivered","client_review","cancelled"]},{"id":"s7","workflow_id":"wf1","key":"delivered","label":"Delivered","stage_group":"delivered","position":6,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["done","approved"]},{"id":"s8","workflow_id":"wf1","key":"done","label":"Done","stage_group":"done","position":7,"is_terminal":true,"wip_guidance":null,"next_stage_keys":[]},{"id":"s9","workflow_id":"wf1","key":"blocked","label":"Blocked","stage_group":"blocked","position":20,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["in_progress","ready","cancelled"]},{"id":"s10","workflow_id":"wf1","key":"waiting","label":"Waiting","stage_group":"waiting","position":21,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["in_progress","cancelled"]},{"id":"s11","workflow_id":"wf1","key":"kiv","label":"KIV","stage_group":"kiv","position":22,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["intake","cancelled"]},{"id":"s12","workflow_id":"wf1","key":"cancelled","label":"Cancelled","stage_group":"cancelled","position":23,"is_terminal":true,"wip_guidance":null,"next_stage_keys":["intake"]},{"id":"v1","workflow_id":"wf2","key":"intake","label":"Intake","stage_group":"intake","position":0,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["ready","cancelled"]},{"id":"v2","workflow_id":"wf2","key":"ready","label":"Ready","stage_group":"ready","position":1,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["shooting","cancelled"]},{"id":"v3","workflow_id":"wf2","key":"shooting","label":"Shooting","stage_group":"active","position":2,"is_terminal":false,"wip_guidance":2,"next_stage_keys":["editing","blocked","cancelled"]},{"id":"v4","workflow_id":"wf2","key":"editing","label":"Editing","stage_group":"active","position":3,"is_terminal":false,"wip_guidance":3,"next_stage_keys":["client_review","shooting","blocked","cancelled"]},{"id":"v5","workflow_id":"wf2","key":"client_review","label":"Client review","stage_group":"client_review","position":4,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["approved","revision","cancelled"]},{"id":"v6","workflow_id":"wf2","key":"revision","label":"Revision","stage_group":"active","position":5,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["client_review","cancelled"]},{"id":"v7","workflow_id":"wf2","key":"approved","label":"Approved","stage_group":"approved","position":6,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["delivered","cancelled"]},{"id":"v8","workflow_id":"wf2","key":"delivered","label":"Delivered","stage_group":"delivered","position":7,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["done"]},{"id":"v9","workflow_id":"wf2","key":"done","label":"Done","stage_group":"done","position":8,"is_terminal":true,"wip_guidance":null,"next_stage_keys":[]},{"id":"v10","workflow_id":"wf2","key":"blocked","label":"Blocked","stage_group":"blocked","position":20,"is_terminal":false,"wip_guidance":null,"next_stage_keys":["shooting","editing","cancelled"]},{"id":"v11","workflow_id":"wf2","key":"cancelled","label":"Cancelled","stage_group":"cancelled","position":23,"is_terminal":true,"wip_guidance":null,"next_stage_keys":["intake"]}],"ops_task_templates":[{"id":"tpl1","name":"Reel","deliverable_type":"reel","workflow_id":"wf2","default_complexity":"standard","first_draft_offset_business_days":3,"final_offset_business_days":7,"default_estimate_minutes":180,"required_fields":{},"checklist":["Script approved","Footage backed up"],"active":true},{"id":"tpl2","name":"Static graphic","deliverable_type":"graphic","workflow_id":"wf1","default_complexity":"simple","first_draft_offset_business_days":2,"final_offset_business_days":4,"default_estimate_minutes":60,"required_fields":{},"checklist":[],"active":true}],"ops_template_variants":[{"id":"tv1","template_id":"tpl1","format":"reels_30","estimate_minutes":180},{"id":"tv2","template_id":"tpl1","format":"reels_60","estimate_minutes":240},{"id":"tv3","template_id":"tpl1","format":"reels_120","estimate_minutes":300},{"id":"tv4","template_id":"tpl2","format":"static","estimate_minutes":60},{"id":"tv5","template_id":"tpl2","format":"gif","estimate_minutes":120},{"id":"tv6","template_id":"tpl2","format":"carousel","estimate_minutes":120}],"health_wordings":[{"version":1,"made_at":"2026-10-06T16:00:00Z","care":["Life at work and life at home both shape how you feel, in body and in mind, and we care about all of it. Every two weeks, take a quiet moment to tell us how you really are.","Please answer honestly. There are no right or wrong answers, only a true picture that helps us look after you. If something feels heavy, ask for a talk: reaching out early is a strength, and we would always rather hear from you and help."],"terms":["Every two weeks: five questions on your body, mind, sleep, energy and workload, each from 1 to 5, with a note if you wish.","ADspace management reads your answers with your name, only to understand how you are and to support you.","Your answers are never part of your performance review.","You can withdraw at any time here, and your answers leave management's view."]}]};
  /* Today's day in Malaysia, and moments relative to now, so the demo is
     always current: a week of tasks due, last month's reports owed, two
     years of clients behind the Dashboard and Analytics. */
  var NOW = Date.now();
  function ago(d, h) { return new Date(NOW - d * 864e5 - (h || 0) * 36e5).toISOString(); }
  function ahead(d, h) { return new Date(NOW + d * 864e5 + (h || 0) * 36e5).toISOString(); }
  function myt(ms) { return new Date(ms + 8 * 36e5); }
  function dayOf(iso) { return myt(Date.parse(iso)).toISOString().slice(0, 10); }
  var T = myt(NOW), TY = T.getUTCFullYear(), TM = T.getUTCMonth();
  function period(back) { var d = new Date(Date.UTC(TY, TM - back, 1)); return d.toISOString().slice(0, 7); }
  function monthStart(back) { return Date.UTC(TY, TM - back, 1) - 8 * 36e5; }
  function lastDay(p) { var y = +p.slice(0, 4), m = +p.slice(5, 7); return p + '-' + String(new Date(Date.UTC(y, m, 0)).getUTCDate()).padStart(2, '0'); }
  function at(ms) { return new Date(Math.min(ms, NOW - 36e5)).toISOString(); }
  var r = 20261027;
  function rand() { r = (r * 1103515245 + 12345) % 2147483648; return r / 2147483648; }
  function pick(a) { return a[Math.floor(rand() * a.length)]; }

  var DB = { activity_log: [], client_contacts: [], client_touches: [], client_services: [], quotations: [], client_detail_forms: [],
    client_checklists: [], client_documents: [], client_requests: [], client_document_services: [], client_document_seq: [],
    client_document_deletions: [], documents: [], creator_profile_changes: [], option_qc: [], campaign_confirmations: [],
    option_posts: [], option_reviews: [], campaign_deliverables: [], ops_task_events: [], ops_task_links: [], link_qrs: [],
    ops_task_checklist_items: [], ops_video_details: [], ops_work_sessions: [], ops_due_requests: [], perf_reviews: [],
    perf_breaches: [], perf_disputes: [], perf_events: [], perf_unlocks: [], perf_attempts: [], perf_initiatives: [],
    perf_reflections: [], perf_self_ratings: [], health_consents: [], health_log: [], health_checkins: [], health_talks: [],
    client_brands: [], meta_links: [], sm_report_audits: [], sm_report_platforms: [], sm_report_posts: [], sm_report_versions: [],
    sm_report_ads: [], handbook_versions: [], video_script_scenes: [], ops_recurring_rules: [], ops_recurring_made: [],
    ops_engagement_checks: [], ops_engagement_events: [], rate_card_versions: [], batches: [], posts: [], reviews: [],
    supplier_forms: [], ops_notifications: [] };
  for (var k in S) DB[k] = S[k];
  DB.perf_code = '';
  DB.perf_people = [];

  /* The team: six colleagues of a made-up agency. The demo signs in as the
     first, who holds every section. */
  DB.team_roles = [
    { slug: 'admin', name: 'Admin', is_admin: true, position: 0 },
    { slug: 'account', name: 'Marketing', is_admin: false, position: 1,
      access: { ops: 'work', clients: 'work', whatsapp: 'work', review: 'work', scripts: 'work', campaigns: 'work', links: 'work', services: 'view', reports: 'work' } },
    { slug: 'creative', name: 'Creative', is_admin: false, position: 2,
      access: { ops: 'work', clients: 'view', review: 'work', scripts: 'work', campaigns: 'view', reports: 'view' } },
    { slug: 'sales', name: 'Sales', is_admin: false, position: 3,
      access: { clients: 'work', whatsapp: 'work', services: 'view', reports: 'view' } }];
  var TEAM = [
    ['d0', 'Alex Tan', 'admin', 'Managing Director', 'marketing'],
    ['d1', 'Mei Ling Chan', 'account', 'Account Manager', 'marketing'],
    ['d2', 'Daniel Wong', 'creative', 'Graphic Designer', 'creative'],
    ['d3', 'Nur Aina', 'account', 'Social Media Executive', 'marketing'],
    ['d4', 'Ravi Kumar', 'sales', 'Sales Executive', 'marketing'],
    ['d5', 'Sophie Lee', 'creative', 'Video Editor', 'creative']];
  DB.team_members = TEAM.map(function (t, i) {
    var role = DB.team_roles.filter(function (g) { return g.slug === t[2]; })[0];
    var first = t[1].split(' ')[0].toLowerCase();
    return { id: t[0], name: t[1], email: first + '@example.com', role: t[2], is_admin: t[2] === 'admin', active: true,
      access: role.access || null, staff_code: 'SS00' + (i + 1), designation: t[3], department: t[4],
      role_family: t[4] === 'creative' ? 'creative' : 'marketing', capacity_minutes_week: 2400,
      card_key: 'demo' + 'abcdef'.charAt(i) + 'k2m', card_slug: first + 'demo', card_on: true, card_mobile: true,
      mobile: '012-345 67' + (10 + i), created_at: ago(700 - i * 60), updated_at: ago(30), last_seen_at: ago(0, i + 1) };
  });
  var who = function (id) { return DB.team_members.filter(function (m) { return m.id === id; })[0].name; };

  /* 48 made-up businesses over two years: a lead in, then won, lost, paused
     or gone, in the order they came. A Active, Z Paused, P left after
     Active, L lost as a lead; l, c and p the leads still open. */
  var BRANDS = [
    ['Bayview Residences', 'Property'], ['Kopi Corner', 'F&B'], ['Lumi Skin Studio', 'Wellness'], ['Urban Fit Gym', 'Wellness'],
    ['Northpoint Motors', 'Automotive'], ['Little Sprouts Academy', 'Education'], ['Maple Home Living', 'Lifestyle'], ['Sunrise Bakehouse', 'F&B'],
    ['Velvet Bridal House', 'Lifestyle'], ['Peak Outdoor Supply', 'Retail'], ['Jade Garden Kitchen', 'F&B'], ['Brightway Tuition', 'Education'],
    ['Coral Bay Retreat', 'Lifestyle'], ['Tech Haven Gadgets', 'Tech'], ['Golden Grain Foods', 'Retail'], ['Bloom & Petal Florist', 'Retail'],
    ['Summit Freight', 'Other'], ['Pure Spring Water', 'Retail'], ['Harbour Smile Dental', 'Wellness'], ['Cedar Lane Homes', 'Property'],
    ['Mango Tree Café', 'F&B'], ['Silverline Auto Care', 'Automotive'], ['Starlight Dance Studio', 'Education'], ['Ocean Breeze Seafood', 'F&B'],
    ['Nova Interiors', 'Lifestyle'], ['Greenfield Organics', 'Retail'], ['Pixel Point Electronics', 'Tech'], ['Riverside Suites', 'Property'],
    ['Kinetic Physio', 'Wellness'], ['Saffron Spice House', 'F&B'], ['Aurora Optics', 'Retail'], ['Willow Kids Wear', 'Retail'],
    ['Metro Laundry Co', 'Other'], ['Evergreen Landscapes', 'Other'], ['Crescent Bakery', 'F&B'], ['Lotus Yoga Centre', 'Wellness'],
    ['Ironclad Hardware', 'Retail'], ['Blue Lagoon Swim School', 'Education'], ['Amber Candle Co', 'Lifestyle'], ['Highland Tea Room', 'F&B'],
    ['Vista Property Group', 'Property'], ['Swift Courier', 'Other'], ['Rosewood Furniture', 'Lifestyle'], ['Prime Cuts Butchery', 'F&B'],
    ['Zen Garden Spa', 'Wellness'], ['Apex Coding School', 'Education'], ['Cloudnine Bedding', 'Lifestyle'], ['Fresh Press Juicery', 'F&B']];
  var FATE = 'ALPALZALAPLALALPAZLALAPLALAZLAPALALALAAlLApcAlpcp';
  var SOURCES = ['referral', 'website', 'instagram', 'facebook', 'website', 'referral', 'tiktok', 'event', 'whatsapp', 'outreach'];
  var OWNERS = ['d1', 'd3', 'd1', 'd4'];
  var FIRST = ['Jason', 'Michelle', 'Farah', 'Kelvin', 'Priya', 'Wei Jie', 'Hannah', 'Aiman', 'Grace', 'Marcus', 'Siti', 'Brandon'];
  var LAST = ['Lim', 'Ng', 'Rahman', 'Teo', 'Nair', 'Goh', 'Yap', 'Ismail', 'Chong', 'Lee', 'Hassan', 'Koh'];
  var SAL = ['Mr', 'Ms', 'Ms', 'Mr', 'Ms', 'Mr', 'Ms', 'Encik', 'Ms', 'Mr', 'Puan', 'Mr'];
  var RATES = [1800, 2800, 3600, 2800, 4800, 2800, 3600];
  var code = 100;
  DB.clients = [];
  BRANDS.forEach(function (b, i) {
    var f = FATE.charAt(i) || 'L';
    var back = 23 - Math.floor(i / 2);
    var born = monthStart(back) + (i % 2 ? 18 : 5) * 864e5 + 10 * 36e5;
    if (born > NOW - 2 * 864e5) born = NOW - (3 + i % 4) * 864e5;
    /* A lead still open came in over the last three weeks. */
    if ('lcp'.indexOf(f) > -1) born = NOW - (2 + (i * 7) % 19) * 864e5 - 3 * 36e5;
    var log = [{ stage: 'lead', at: at(born) }];
    var stage = 'lead', reason = null, note = null, won = null;
    function step(s, d) { var t = born + d * 864e5; if (t > NOW - 36e5) return false; log.push({ stage: s, at: at(t) }); stage = s; return true; }
    if (f !== 'l') step('contacted', 2);
    if ('AZPpL'.indexOf(f) > -1 && f !== 'L') step('proposal', 9);
    if ('AZP'.indexOf(f) > -1 && step('active', 18 + (i % 3) * 4)) won = born + (18 + (i % 3) * 4) * 864e5;
    if (f === 'L') { step('past', 16 + i % 9); reason = pick(['budget', 'no_reply', 'other', 'budget', 'no_reply']); }
    if (f === 'P' && won) { if (step('past', Math.min(300 + (i % 5) * 40, (NOW - born) / 864e5 - 20))) reason = pick(['budget', 'results', 'in_house', 'closed']); }
    if (f === 'Z' && won) { if (step('paused', Math.min(200 + (i % 4) * 30, (NOW - born) / 864e5 - 12))) reason = pick(['budget', 'other']); }
    if (reason === 'other') note = 'Moving the budget to a product launch next quarter.';
    if (reason) { log[log.length - 1].reason = reason; if (note) log[log.length - 1].note = note; }
    var slug = b[0].toLowerCase().replace(/&/g, 'and').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
    var id = 'dc' + (i + 1);
    var activeOnce = won !== null;
    var c = { id: id, slug: slug, name: b[0], industry: b[1], stage: stage, market: i % 9 === 4 ? 'SG' : 'MY', source: SOURCES[i % SOURCES.length],
      owner: who(OWNERS[i % OWNERS.length]), sales_by: 'd4', sst_applies: true, created_at: at(born), stage_since: log[log.length - 1].at,
      stage_log: log, stage_reason: reason, stage_note: note, review_hidden: stage !== 'active', active: true,
      updated_at: log[log.length - 1].at, commence: null, website: 'https://example.com',
      handle_ig: slug.replace(/-/g, '.'), handle_fb: slug.replace(/-/g, ''), logo_url: null };
    if (activeOnce) {
      code++;
      c.client_code = 'AC' + code;
      c.legal_name = b[0].toUpperCase().replace(/&/g, 'AND').replace(/[^A-Z0-9 ]/g, '') + ' SDN BHD';
      c.company_no = '2020010' + String(10000 + i * 37).slice(-5);
      c.billing_address = (10 + i) + ' Jalan Contoh ' + (i % 7 + 1) + ', 81100 Johor Bahru, Johor';
      c.finance_email = 'accounts@example.com';
    }
    /* The links a client is sent: the review page and the video scripts. */
    if (stage === 'active') { c.access_token = 'drv' + String(10000 + i).slice(-5); c.script_key = 'dsk' + String(10000 + i).slice(-5); }
    if (stage === 'active' && (i === 0 || i === 4)) { c.vic_at = ago(40); c.vic_by = 'd0'; c.vic_note = 'Group account. Approvals go to the director.'; }
    if (stage === 'active') c.brief = { audience: 'Young families and working adults in Johor Bahru.', pillars: 'Product, behind the scenes, customer stories.', tone: 'Warm, clear and friendly.' };
    DB.clients.push(c);
    var ct = { id: 'dk' + (i + 1), client_id: id, salutation: SAL[i % 12], name: FIRST[i % 12] + ' ' + LAST[(i * 5) % 12],
      role: pick(['Owner', 'Marketing Manager', 'Director', 'Brand Manager']), phone: '012-3' + String(100000 + i * 731).slice(-6).replace(/^(\d\d)/, '$1 '),
      email: FIRST[i % 12].toLowerCase().replace(/ /g, '') + '@example.com', whatsapp: null, lang: i % 4 === 1 ? 'zh' : 'en', is_primary: true,
      created_at: at(born), archived_at: null, portal_access: stage === 'active' && i % 3 === 0 };
    DB.client_contacts.push(ct);
    if (activeOnce) {
      var rate = RATES[i % RATES.length];
      DB.client_services.push({ id: 'ds' + (i + 1), client_id: id, service_slug: 'pkg-' + (rate >= 3600 ? 'c' : rate >= 2800 ? 'b' : 'a'),
        label: rate >= 3600 ? 'Package C · 3 platforms · 8 contents' : rate >= 2800 ? 'Package B · 2 platforms · 4 contents' : 'Package A · 1 platform · 4 contents',
        qty: 1, rate: rate, unit: 'month', state: 'confirmed', tenure: 12, start_on: dayOf(at(won)), term_adjust: true, term_pct: -5,
        created_at: at(won - 5 * 864e5), archived_at: null, tax_code: 'SV8' });
    }
    if ('lcp'.indexOf(f) > -1 || (stage === 'active' && i % 2 === 0)) {
      var lead = 'lcp'.indexOf(f) > -1;
      DB.client_touches.push({ id: 'dt' + (i + 1), client_id: id, kind: pick(['call', 'meeting', 'visit']), happened_at: ago(1 + i % 6, 3),
        by_whom: c.owner, contact_name: ct.name, summary: lead ? 'Walked through the packages and the content calendar. Interested in two platforms.' : 'Monthly check-in. Happy with last month\'s reels; asked for more product posts.',
        next_action: lead ? (f === 'p' ? 'Follow up on the quotation' : 'Send the proposal') : null, next_at: lead ? dayOf(ahead(1 + i % 4)) : null,
        created_at: ago(1 + i % 6, 3), updated_at: ago(1 + i % 6, 3), archived_at: null, done_at: null });
    }
  });
  var ACTIVE = DB.clients.filter(function (c) { return c.stage === 'active'; });
  /* The client portal's demo signs in as the first active client's main contact. */
  DB.client_contacts.forEach(function (k) { if (k.client_id === ACTIVE[0].id && k.is_primary) { k.email = 'client@example.com'; k.portal_access = true; } });

  /* My Work: this month and last for every active client, four posts a
     month and its report, spread across the team and the workflow. */
  DB.ops_engagements = []; DB.ops_tasks = []; DB.ops_task_assignees = [];
  var no = 1000, aid = 0;
  var MAKERS = ['d2', 'd0', 'd5', 'd3', 'd0'];
  var FMT = [['static', 'Product highlight'], ['reels_30', 'Behind the scenes'], ['carousel', 'Customer story'], ['reels_60', 'How it works'], ['static', 'Promotion']];
  /* Where a post has been, stage by stage, so on time and the stage times
     read as they would: most reach client review the day before their due
     date, one in seven a day late. */
  var LINE = ['ready', 'in_production', 'internal_review', 'client_review', 'approved', 'scheduled', 'live', 'performance_review', 'completed'];
  var evn = 0;
  function history(t, dueMs, late) {
    var pub = Date.parse(t.publish_at), made = Date.parse(t.created_at);
    var when = { ready: made, in_production: dueMs - 6 * 864e5, internal_review: dueMs - 3 * 864e5,
      client_review: dueMs - (late ? -1.5 : 1) * 864e5, revision_client: dueMs + 864e5, approved: dueMs + 1.5 * 864e5, scheduled: dueMs + 2 * 864e5,
      live: pub + (late ? 864e5 : 0), performance_review: pub + 7 * 864e5, completed: pub + 8 * 864e5 };
    var last = t.stage_key === 'revision_client' ? 3 : LINE.indexOf(t.stage_key);
    var path = LINE.slice(0, last + 1);
    if (t.stage_key === 'revision_client') path.push('revision_client');
    var from = null;
    path.forEach(function (k) {
      var ms = Math.min(when[k], NOW - 36e5);
      DB.ops_task_events.push({ id: 'dev' + (++evn), task_id: t.id, event_type: from ? 'stage_changed' : 'task_created',
        from_value: from ? { stage_key: from } : null, to_value: { stage_key: k }, detail: {}, actor_id: t.manager_id,
        actor_email: null, source: 'portal', created_at: new Date(ms).toISOString() });
      if (k === 'live') t.live_at = new Date(ms).toISOString();
      from = k;
    });
  }
  function task(o, dueMs, late) {
    no++;
    var t = { id: 'dw' + no, task_no: no, scope: 'client', campaign_id: null, batch_id: null, source_type: null, source_id: null,
      parent_task_id: null, template_id: null, description: null, remarks: null, deliverable_type: 'static', language_codes: [],
      priority_level: 3, complexity: 'standard', estimate_minutes: 120, publish_at: null, original_first_draft_due_at: null,
      current_first_draft_due_at: null, first_draft_submitted_at: null, delivered_at: null, completed_at: null,
      blocked_category: null, blocked_note: null, blocked_at: null, task_type: 'engagement', code: null, code_period: null,
      code_week: null, code_seq: null, content_desc: null, engagement_id: null, manager_id: 'd1', created_by: 'd1',
      created_at: ago(20), updated_at: ago(1), archived_at: null, cancelled_at: null, version: 1, workflow_id: 'wf3', stage_key: 'ready' };
    for (var k in o) t[k] = o[k];
    t.original_final_due_at = t.original_final_due_at || t.current_final_due_at;
    DB.ops_tasks.push(t);
    if (o.owner) DB.ops_task_assignees.push({ id: 'da' + (++aid), task_id: t.id, team_member_id: o.owner, responsibility: 'owner',
      assigned_by: 'd1', started_at: t.created_at, ended_at: null });
    delete t.owner;
    if (dueMs && t.workflow_id === 'wf3') history(t, dueMs, late);
    return t;
  }
  var REPORTED = ['published', 'published', 'published', 'confirmed', 'published', 'draft', 'published', 'published', 'review', 'published', 'published', 'published', 'published'];
  function reportOf(ci) { return ci % 9 === 8 ? null : REPORTED[ci % 13]; }
  function sentOf(ci) { return reportOf(ci) === 'published'; }
  var NOWSTAGES = ['in_production', 'internal_review', 'client_review', 'approved', 'scheduled', 'ready', 'revision_client', 'live'];
  ACTIVE.forEach(function (c, ci) {
    [1, 0].forEach(function (back) {
      var p = period(back);
      var eid = 'de' + c.id + '-' + p;
      var mgr = c.owner === 'Nur Aina' ? 'd3' : 'd1';
      DB.ops_engagements.push({ id: eid, client_id: c.id, period: p, manager_id: mgr, planned_count: 4, status: back ? 'completed' : 'open',
        meeting_at: at(monthStart(back) + 2 * 864e5 + 6 * 36e5), meeting_channel: 'google_meet', meeting_minutes: 45,
        meeting_link: 'https://meet.google.com/abc-defg-hij', meeting_owner_id: mgr, meeting_na: false, reports: ['social'],
        start_day: 1, created_by: mgr, created_at: at(monthStart(back) - 5 * 864e5), updated_at: ago(2), version: 1 });
      for (var n = 1; n <= 4; n++) {
        var f = FMT[(ci + n) % FMT.length], wk = n;
        var cd = p.slice(2, 4) + p.slice(5, 7) + 'W' + wk + String(n).padStart(2, '0');
        var dueMs = monthStart(back) + (wk * 7 - 1) * 864e5 + 10 * 36e5;
        var st = back ? 'completed' : NOWSTAGES[(ci + n) % NOWSTAGES.length];
        /* A post's stage follows its dates, one in nine left behind. */
        var pubMs = dueMs + 3 * 864e5;
        if (!back && (ci + n) % 9) {
          if (pubMs + 8 * 864e5 < NOW) st = 'completed';
          else if (pubMs < NOW) st = 'live';
          else if (dueMs < NOW && ['approved', 'scheduled'].indexOf(st) < 0) st = (ci + n) % 2 ? 'scheduled' : 'approved';
        }
        task({ title: cd + ' ' + f[1], code: cd, code_period: p, code_week: wk, code_seq: n, content_desc: f[1], client_id: c.id,
          engagement_id: eid, deliverable_type: f[0], stage_key: st, owner: MAKERS[(ci + n) % MAKERS.length], manager_id: mgr,
          priority_level: (ci + n) % 9 === 0 ? 2 : 3, priority_at: ago(1),
          current_first_draft_due_at: at(dueMs - 3 * 864e5), original_first_draft_due_at: at(dueMs - 3 * 864e5),
          current_final_due_at: new Date(dueMs).toISOString(), publish_at: new Date(dueMs + 3 * 864e5).toISOString(),
          created_at: at(monthStart(back) - 3 * 864e5), completed_at: back || st === 'completed' ? at(pubMs + 8 * 864e5) : null,
          delivered_at: back ? at(dueMs) : null }, dueMs, (ci * 4 + n) % 7 === 0);
      }
      if (back) {
        task({ title: 'Social Media Accounts Report', client_id: c.id, engagement_id: eid, workflow_id: 'wf4', source_type: 'report_social',
          stage_key: { published: sentOf(ci) ? 'complete' : 'review', confirmed: 'waiting', review: 'waiting', draft: 'doing' }[reportOf(ci)] || 'todo',
          completed_at: sentOf(ci) ? ago(2) : null, deliverable_type: 'other', task_type: 'engagement', owner: mgr,
          current_final_due_at: new Date(Date.parse(lastDay(p) + 'T15:59:00Z') + 7 * 864e5).toISOString() });
      }
    });
  });
  /* Everyday work beside the clients'. */
  [['Update the rate card for next year', 'd0', 6, 'doing'], ['Prepare the team offsite agenda', 'd1', 9, 'todo'],
   ['Renew the stock photo licence', 'd2', -2, 'todo'], ['Shortlist editing interns', 'd5', 4, 'waiting']].forEach(function (x) {
    task({ title: x[0], scope: 'internal', client_id: null, workflow_id: 'wf4', stage_key: x[3], task_type: 'adhoc', deliverable_type: 'other',
      owner: x[1], current_final_due_at: x[2] < 0 ? ago(-x[2]) : ahead(x[2]) });
  });

  /* Reports for last month: most published, some on their way. */
  DB.sm_reports = [];
  var LM = period(1);
  ACTIVE.forEach(function (c, ci) {
    var st = reportOf(ci);
    if (!st) return;
    var rid = 'dr' + c.id;
    DB.sm_reports.push({ id: rid, client_id: c.id, kind: 'social', title: 'Social Media Accounts Report', period_start: LM + '-01',
      period_end: lastDay(LM), status: st, version_no: 1, created_by: 'd1', created_at: ago(9), updated_at: ago(2), insights: {},
      submitted_by: st === 'draft' ? null : 'd3', submitted_at: st === 'draft' ? null : ago(5), reviewer_id: st === 'draft' ? null : 'd1',
      confirmed_by: st === 'published' || st === 'confirmed' ? 'd1' : null, confirmed_at: st === 'published' || st === 'confirmed' ? ago(4) : null,
      sent_on: sentOf(ci) ? dayOf(ago(2)) : null, sent_by: sentOf(ci) ? 'd1' : null, brand_id: null,
      brand_name: null, on_request: false, lang: 'en' });
    [['instagram', 'Instagram', 1840, 2010], ['facebook', 'Facebook', 3120, 3185]].forEach(function (pl, pi) {
      var pid = rid + '-' + pl[0];
      DB.sm_report_platforms.push({ id: pid, report_id: rid, platform: pl[0], account_name: c.handle_ig, position: pi,
        followers_start: pl[2] + ci * 37, followers_end: pl[3] + ci * 41, metrics: { reach: 12000 + ci * 900, views: 18500 + ci * 1200, interactions: 640 + ci * 31 },
        summary: null, worked: null, improve: null, actions: null, created_at: ago(9) });
      for (var q = 0; q < 4; q++) DB.sm_report_posts.push({ id: pid + '-' + q, report_id: rid, platform_id: pid,
        posted_on: LM + '-' + String(4 + q * 7).padStart(2, '0'), title: FMT[q][1], caption: 'A new look at what we do best. Visit us this weekend.',
        content_type: q % 2 ? 'reel' : 'image', url: 'https://example.com/post/' + pid + q, views: 2400 + q * 830 + ci * 40, reach: 1900 + q * 610,
        impressions: 2900 + q * 900, interactions: 80 + q * 26, engagements: 96 + q * 31, likes: 70 + q * 20, comments: 6 + q, shares: 3 + q, saves: 5 + q,
        position: q, created_at: ago(9) });
    });
    if (st === 'published') DB.sm_report_versions.push({ id: rid + 'v1', report_id: rid, version_no: 1, snapshot: {}, published_by: 'd1', published_at: ago(3), withdrawn_at: null });
  });

  /* Content Review: this month's sets for three clients, posts in every state. */
  var PH = [['ph-feed-1.svg', 'instagram', 'feed', 1080, 1350], ['ph-reel-1.svg', 'instagram', 'reel', 1080, 1920], ['ph-carousel-1.svg', 'instagram', 'feed', 1080, 1350],
    ['ph-fb-1.svg', 'facebook', 'feed', 1200, 1200], ['ph-tiktok-1.svg', 'tiktok', 'reel', 1080, 1920], ['ph-xhs-1.svg', 'xhs', 'feed', 1080, 1440]];
  ACTIVE.forEach(function (c, ci) {
    var bid = 'db' + c.id;
    DB.batches.push({ id: bid, client_id: c.id, title: 'This month\'s posts', published: ci % 6 !== 5, period: period(0),
      created_at: ago(8), published_at: ci % 6 !== 5 ? ago(7) : null, note: null });
    PH.forEach(function (ph, pi) {
      var id = bid + 'p' + pi;
      DB.posts.push({ id: id, batch_id: bid, platform: ph[1], format: ph[2], handle: c.handle_ig, title: FMT[pi % FMT.length][1],
        caption: 'Something new is coming to ' + c.name + '. Save this post and tag a friend who needs to see it.',
        media: [{ url: '/demo/' + ph[0], type: 'image', width: ph[3], height: ph[4] }], position: pi, round: 1, content_version: 1, created_at: ago(8) });
      if (ci % 6 !== 5 && pi < (ci % 3 ? 6 : 4)) DB.reviews.push({ id: id + 'r', post_id: id, decision: pi === 2 ? 'changes' : 'approved', round: 1,
        note: pi === 2 ? 'Please use the warmer photo from the shoot.' : null, reviewer: pick(FIRST), source: 'client', created_at: ago(3 - pi * 0.4) });
    });
  });

  /* Creator Campaigns: one in production and one open for the client's selection. */
  DB.creators = [['Amelia Chen', 12400, 380], ['Hafiz Rahman', 8100, 320], ['Chloe Tan', 30200, 650], ['Daniel Ho', 15600, 450],
    ['Siti Aisyah', 21800, 560], ['Jessica Lau', 6400, 280]].map(function (k, i) {
    return { id: 'dcr' + i, name: k[0], followers: k[1], cost_rate: Math.round(k[2] * 0.75), client_rate: k[2], industries: 'lifestyle',
      active: true, access_code: 'DEMO' + 'ABCDEF'.charAt(i) + 'XYZ', created_at: ago(300 - i * 20) };
  });
  DB.creator_profiles = DB.creators.map(function (k, i) {
    var h = k.name.toLowerCase().replace(/ /g, '.');
    return { id: 'dcp' + i, creator_id: k.id, platform: i % 2 ? 'xhs' : 'instagram', url: i % 2 ? 'https://www.xiaohongshu.com/user/profile/demo' + i : 'https://instagram.com/' + h, handle: i % 2 ? null : h };
  });
  DB.campaigns = [
    { id: 'dcm1', client_id: ACTIVE[0].id, title: 'Weekend Open House', slots: 3, state: 'production', deliverable: 'video', push_format: 'site_visit',
      access_token: 'demo2cmp', owner: 'Mei Ling Chan', created_at: ago(30), updated_at: ago(2), deadline: dayOf(ahead(12)), brief: 'Tour the show unit and share why it suits young families.' },
    { id: 'dcm2', client_id: ACTIVE[1].id, title: 'Festive Menu Launch', slots: 2, state: 'open', deliverable: 'video', push_format: 'site_visit',
      access_token: 'demo3cmp', owner: 'Nur Aina', created_at: ago(6), updated_at: ago(1), deadline: dayOf(ahead(20)), brief: 'Try the festive set and film the first bite.' }];
  DB.campaign_options = [
    { id: 'dco1', campaign_id: 'dcm1', creator_id: 'dcr0', rate: 380, platforms: 'instagram', state: 'submitted', submitted_at: ago(1), added_at: ago(28), position: 0, revision_round: 1 },
    { id: 'dco2', campaign_id: 'dcm1', creator_id: 'dcr2', rate: 650, platforms: 'instagram', state: 'pending_draft', submission_due: dayOf(ahead(4)), visit_date: dayOf(ago(3)), added_at: ago(28), position: 1 },
    { id: 'dco3', campaign_id: 'dcm1', creator_id: 'dcr3', rate: 450, platforms: 'instagram', state: 'pending_visit', visit_date: dayOf(ahead(3)), visit_time: '14:00', visit_location: 'Show unit, Level 2', added_at: ago(28), position: 2 },
    { id: 'dco4', campaign_id: 'dcm2', creator_id: 'dcr1', rate: 320, platforms: 'xhs', state: 'option', added_at: ago(5), position: 0 },
    { id: 'dco5', campaign_id: 'dcm2', creator_id: 'dcr4', rate: 560, platforms: 'instagram', state: 'option', added_at: ago(5), position: 1 },
    { id: 'dco6', campaign_id: 'dcm2', creator_id: 'dcr5', rate: 280, platforms: 'xhs', state: 'option', added_at: ago(5), position: 2 }];

  /* Video Scripts: three for one client this month. */
  DB.video_scripts = [['Show unit walkthrough', 'scenes'], ['Meet the team', 'story'], ['Three reasons to visit', 'scenes']].map(function (s, i) {
    var p = period(0);
    return { id: 'dvs' + i, client_id: ACTIVE[0].id, period: p, seq: i + 1, code: p.slice(2, 4) + p.slice(5, 7) + 'VS0' + (i + 1), kind: s[1], title: s[0],
      platform: 'Instagram', language: 'English', shoot_on: dayOf(ahead(5 + i)), shoot_time: '10:00', venue: 'Show unit', duration_minutes: 60,
      status: i ? 'draft' : 'shared', shared_at: i ? null : ago(2), round: 1, version: 1, created_by: 'd3', created_by_name: 'Nur Aina',
      created_at: ago(6), updated_at: ago(2), updated_by_name: 'Nur Aina' };
  });
  DB.video_scripts.forEach(function (s) {
    [['Wide shot of the entrance at golden hour.', 'Welcome home.'], ['Close up of the kitchen counter.', 'Every corner made for family time.'],
     ['Host walks to the balcony.', 'And this view is yours every morning.']].forEach(function (x, i) {
      DB.video_script_scenes.push({ id: s.id + 's' + i, script_id: s.id, position: i, visual: x[0], line: x[1], vc: null });
    });
  });

  /* A sample rate card. */
  DB.services = [
    { slug: 'static-graphic', category: 'Content', name: 'Static graphic', rate: 300, unit: 'Per post', position: 10, active: true },
    { slug: 'reels-60', category: 'Content', name: 'Reels, up to 60 seconds', rate: 750, unit: 'Per video', position: 14, active: true },
    { slug: 'pkg-a', category: 'Monthly packages', name: 'Package A · 1 platform · 4 contents', rate: 1800, unit: 'Per month, 6 month minimum', position: 40, active: true, min_months: 6,
      spec: { role: 'plan', plan: 'A', ads: false, platforms: 1, contents: 4, mix: [{ graphic: 2, reel: 2 }], best_for: 'Brands starting out on social media' },
      detail: '1 platform\n4 contents each month: 2 graphics and 2 reels\nContent posting and community replies\nMonthly accounts report' },
    { slug: 'pkg-b', category: 'Monthly packages', name: 'Package B · 2 platforms · 4 contents', rate: 2800, unit: 'Per month, 6 month minimum', position: 41, active: true, min_months: 6,
      spec: { role: 'plan', plan: 'B', ads: false, platforms: 2, contents: 4, mix: [{ graphic: 1, reel: 3 }, { reel: 4 }], best_for: 'Brands building steady momentum' },
      detail: 'Up to 2 platforms\n4 contents each month\nContent planning and copywriting\nMonthly accounts report' },
    { slug: 'pkg-c', category: 'Monthly packages', name: 'Package C · 3 platforms · 8 contents', rate: 3600, unit: 'Per month, 6 month minimum', position: 42, active: true, min_months: 6,
      spec: { role: 'plan', plan: 'C', ads: true, platforms: 3, contents: 8, mix: [{ graphic: 4, reel: 4 }], best_for: 'Brands ready to grow with advertising' },
      detail: 'Up to 3 platforms\n8 contents each month\nMeta advertising management\nMonthly accounts and advertising reports' },
    { slug: 'koc-10', category: 'KOC programmes', name: 'KOC package · 10 creators', rate: 4200, unit: 'Per campaign', position: 50, active: true },
    { slug: 'rev-minor', category: 'Add-ons', name: 'Minor revision', rate: 150, unit: 'Per asset, per round', position: 70, active: true },
    { slug: 'urgent', category: 'Add-ons', name: 'Urgent fee', rate: 120, unit: 'Per affected asset, per round', position: 72, active: true, spec: { role: 'addon', group: 'Revisions & Turnaround' } }];
  DB.rate_card_text = [
    { key: 'cover_title', label: 'Cover title', page: 'Cover', position: 1, value: 'Rate Card & Packages' },
    { key: 'terms', label: 'Terms of Service', page: 'Add-ons', position: 50,
      value: 'All rates are quoted in Ringgit Malaysia (RM) and exclude the applicable 8% Service Tax (SST).\nThis rate card is valid until {valid until}.' }];

  DB.suppliers = [
    { id: 'dsu1', code: 'AS001', name: 'BRIGHT PRINT SDN BHD', kind: 'company', brn: '202101012345', tin: 'C12345678090', phone: '07-123 4567',
      address: '12 Jalan Contoh, 81100 Johor Bahru, Johor', contact_name: 'John Doe', designation: 'Director', email: 'email@example.com',
      mobile: '012-345 6789', payment_term: 'NET 30', currency: 'MYR', payee_name: 'BRIGHT PRINT SDN BHD', status: 'active',
      created_at: ago(200), updated_at: ago(100), approved_at: ago(199), approved_by: 'd0' },
    { id: 'dsu2', code: 'AS002', name: 'Jane Doe', kind: 'individual', email: 'email@example.com', currency: 'MYR', status: 'pending', created_at: ago(5), updated_at: ago(5) }];
  DB.links = [
    { id: 'dl1', slug: 'open-house', target_url: 'https://example.com/open-house', title: 'Open house landing page', active: true, created_at: ago(40) },
    { id: 'dl2', slug: 'menu-qr', target_url: 'https://example.com/menu?utm_source=qr', title: 'Table menu QR', active: true, created_at: ago(90) },
    { id: 'dl3', slug: 'raya-promo', target_url: 'https://example.com/promo', title: 'Last season promotion', active: false, created_at: ago(300) }];
  DB.handbook_docs = [['Employee Handbook', 'handbook'], ['Content Approval SOP', 'sop'], ['Leave Policy', 'policy'], ['Client Onboarding Checklist', 'template']].map(function (h, i) {
    return { id: 'dh' + i, title: h[0], category: h[1], summary: null, link_url: 'https://example.com/handbook/' + i, current_version: 1,
      archived_at: null, created_at: ago(200 - i * 10), created_by: 'd0', updated_at: ago(30 + i) };
  });

  /* What happened lately, newest first in the record. */
  var ACTS = [['Mei Ling Chan', 'task.moved', 0.1], ['Nur Aina', 'client.touch', 0.3], ['Daniel Wong', 'task.moved', 0.5], ['Ravi Kumar', 'client.added', 1],
    ['Mei Ling Chan', 'report.published', 1.4], ['Sophie Lee', 'task.moved', 2], ['Alex Tan', 'set.published', 3], ['Nur Aina', 'campaign.offered', 5]];
  ACTS.forEach(function (a, i) {
    var c = ACTIVE[i % ACTIVE.length];
    DB.activity_log.push({ id: 'dlog' + i, actor: a[0], action: a[1], subject: a[1] === 'client.added' ? DB.clients[DB.clients.length - 1].name : c.name,
      detail: a[1] === 'task.moved' ? 'Moved to Client review' : a[1] === 'client.touch' ? 'Call logged' : '', created_at: ago(a[2]) });
  });
  DB.ops_notifications = [
    { id: 'dn1', team_member_id: 'd0', task_id: DB.ops_tasks[2].id, kind: 'stage_changed', title: 'Moved to Client review', body: 'Mei Ling Chan moved a task to Client review.', read_at: null, created_at: ago(0, 2) },
    { id: 'dn2', team_member_id: 'd0', task_id: null, kind: 'quote.website', title: 'New quotation request', body: 'A prospect asked for a quotation on the website.', read_at: null, created_at: ago(0, 5) },
    { id: 'dn3', team_member_id: 'd0', task_id: DB.ops_tasks[5].id, kind: 'assigned', title: 'Assigned to you', body: 'Daniel Wong handed a task to you.', read_at: ago(1), created_at: ago(1, 3) }];
  return DB;
  };
})();
