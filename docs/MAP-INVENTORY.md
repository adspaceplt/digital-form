# Portal map: inventory (A, C, D)

The detail behind `docs/MAP.md`. Generated on 2026-11-27 at `ca7f5d0` by reading the repository only; every count is a measured baseline, not a target. Line numbers rot: re-run the guards (MAP.md §F) rather than trust a line here.

Wording is never copied here (the repository is public): content is listed by location only.

## A. Entities

- **211 tables** in `supabase/schema.sql` (206 live; 5 created then dropped at :78864–78868). 146 key on a uuid; 65 on text, int, date, boolean or a composite.
- **289 uuid foreign keys** plus **11 text foreign keys** (slug/key columns); 47 FKs state no `on delete` (36 of them to `team_members`).
- **117 non-uuid links** (name, email, code, external id or copied value) and **89 uuid columns with no foreign key** (16 polymorphic): 206 flagged in A.2.

Method: last `create table` body merged with every `alter table … add column / add constraint / drop column` in file order (a one-off parser, not committed). Console = `.from('t')` (weighted ×3) plus RPC names in each `js/*.js` whose function body reads the table directly. Client page = RPC names in the page's own scripts, tables read by the function or one helper it calls (approximate). On delete: cas = cascade, null = set null, rst = restrict, - = not stated (no action). SOFT = uuid column with no FK. `app_flags`, `announcements` reach every client page through `maintenance.js` / `announce.js`.

## A.1 Tables by area

### Clients/sales (39)

| Table | id (type) | Links to (col→table, on delete) | Linked from | Console (top scripts) | Client page |
|---|---|---|---|---|---|
| billing_entities | id (uuid) | bill_contact_id→client_contacts (null); created_by→team_members (null); orphan_of SOFT | client_entities | crm, bukku, quotes | quote via quote_details_submit |
| bukku_doc_marks | kind (text) | — | — | overview, payments, suppliers | — |
| bukku_docs | (kind, doc_id) composite | — | — | quotes, suppliers | — |
| bukku_links | (kind, record_id) composite | record_id SOFT; sent_by→team_members (null) | — | bukku, crm, quotes | — |
| bukku_links_gone | none | record_id SOFT; sent_by SOFT; gone_by→team_members (null) | — | bukku, crm | — |
| bukku_send_claims | (kind, record_id) composite | record_id SOFT; claimed_by SOFT | — | — | — |
| bukku_settings | id (int) | set_by→team_members (null) | — | bukku, agent, campaigns | — |
| client_ad_debtors | client_id (uuid) | client_id→clients (cas); set_by→team_members (null) | — | quotes | — |
| client_brands | id (uuid) | client_id SOFT | meta_links | crm, reports, overview | — |
| client_checklists | id (uuid) | client_id→clients (cas); prepared_by→team_members (null); reviewed_by→team_members (null) | — | checklists, ops, overview | — |
| client_contacts | id (uuid) | client_id→clients (cas) | billing_entities, client_emails, client_requests, clients, feedback_requests, feedback_responses | crm, agent, whatsapp | client via client_billing,feedback_submit…; creators via get_campaign; feedback via feedback_read,feedback_submit; quote via quote_sign_finish,quote_website_read; review via get_review_feed; script via get_scripts |
| client_detail_forms | id (uuid) | client_id→clients (cas); created_by→team_members (null); used_by→team_members (null); quotation_id→quotations (null) | — | crm, search | details via client_details_read,client_details_submit; quote via quote_website_read |
| client_document_deletions | id (uuid) | document_id SOFT; client_id SOFT; service_ids SOFT | — | documents | — |
| client_document_seq | (client_id, ym) composite | client_id→clients (cas) | — | — | — |
| client_document_services | (document_id, service_id) composite | document_id→client_documents (cas); service_id→client_services (rst) | — | documents, crm | quote via quote_website_read |
| client_documents | id (uuid) | client_id→clients (cas); superseded_by→client_documents (null) | client_document_services, client_documents | documents, agent, letters | client via get_portal; quote via quote_website_read; verify via verify_details,verify_details_name… |
| client_entities | (client_id, entity_id) composite | client_id→clients (cas); entity_id→billing_entities (cas); added_by→team_members (null); bill_contact_id SOFT | — | crm, quotes, register | — |
| client_requests | id (uuid) | client_id→clients (cas); contact_id→client_contacts (null); service_id→client_services (null) | — | crm, ops, overview | client via get_portal,portal_request… |
| client_services | id (uuid) | client_id→clients (cas); service_slug→services [text] (null); quotation_id→quotations (-) | client_document_services, client_requests | crm, quotes, ops | client via get_portal,portal_request…; quote via quote_website_read |
| client_touches | id (uuid) | client_id→clients (cas) | outstation_stops | crm, agent, search | client via portal_meetings |
| clients | id (uuid) | bill_contact_id→client_contacts (null); vic_by→team_members (-); sales_by→team_members (-); owner_id→team_members (null); portal_kept_by→team_members (null) | activity_log, batches, brand_analyses, campaigns, client_ad_debtors, client_checklists, client_contacts, client_detail_forms, client_document_seq, client_documents … (+23) | crm, admin, agent | client via client_billing,feedback_submit…; creator via get_creator; creators via confirm_selection_with,get_campaign…; details via client_details_read,client_details_submit; feedback via feedback_read,feedback_submit; quote via industries_list,quote_change_request…; review via get_review_feed,submit_review_seen; script via get_scripts; verify via verify_details,verify_details_name… |
| drive_assets | id (uuid) | client_id→clients (cas) | — | admin | — |
| feedback_hits | ip (text) | — | — | — | client via feedback_submit; feedback via feedback_read,feedback_submit |
| feedback_questions | (kind, key) composite | — | — | analytics, crm, feedback | client via feedback_submit,portal_feedback; feedback via feedback_read,feedback_submit |
| feedback_requests | id (uuid) | client_id→clients (cas); sent_by→team_members (null); contact_id→client_contacts (null); manager_id→team_members (null) | feedback_responses | crm, feedback, analytics | client via feedback_submit,portal_feedback; feedback via feedback_read,feedback_submit |
| feedback_responses | id (uuid) | request_id→feedback_requests (cas); client_id→clients (cas); manager_id→team_members (null); contact_id→client_contacts (null); followup_task_id→ops_tasks (null) | — | crm, feedback, analytics | client via feedback_submit,portal_feedback; feedback via feedback_read,feedback_submit |
| industries | name (text) | updated_by SOFT | — | settings, crm | quote via industries_list,quote_details_submit |
| meta_links | id (uuid) | client_id→clients (cas); brand_id→client_brands (cas) | — | crm, register, reports | — |
| quotation_drafts | id (uuid) | client_id→clients (cas); member_id→team_members (cas) | — | quotes | — |
| quotation_invoices | (quotation_id, cycle, kind) composite | quotation_id→quotations (cas); made_by→team_members (null); claimed_by→team_members (null) | — | quotes | — |
| quotation_link_copies | id (uuid) | quotation_id SOFT | — | quotes | quote via quote_opened |
| quotation_refs_kept | ref (text) | — | — | quotes | — |
| quotations | id (uuid) | client_id→clients (cas); version_id SOFT; replaces→quotations (null); reviewer_id→team_members (null); revises→quotations (null); made_by_id→team_members (null) | client_detail_forms, client_services, quotation_invoices, quotations, quote_sign_codes | quotes, agent, crm | quote via quote_change_request,quote_decline…; verify via verify_details,verify_details_name… |
| quote_hits | ip (text) | — | — | — | quote via quote_preflight |
| quote_sign_codes | id (uuid) | quotation_id→quotations (cas) | — | agent, whatsapp | quote via quote_sign_finish |
| rate_card_text | key (text) | — | — | crm, settings | — |
| rate_card_versions | id (uuid) | — | — | crm, quotes | — |
| services | slug (text) | — | client_services | crm, search, quotes | — |
| tax_codes | code (text) | — | — | settings, delreq, money | — |

### Content Review (4)

| Table | id (type) | Links to (col→table, on delete) | Linked from | Console (top scripts) | Client page |
|---|---|---|---|---|---|
| batches | id (uuid) | client_id→clients (cas) | ops_tasks, posts | admin, agent, ops | client via get_portal,portal_work; review via get_review_feed,submit_review_seen |
| post_versions | id (uuid) | post_id→posts (cas) | — | admin | — |
| posts | id (uuid) | batch_id→batches (cas); cover_for SOFT | ops_task_links, post_versions, reviews | admin, ops, api | client via portal_work; review via get_review_feed,submit_review_seen |
| reviews | id (uuid) | post_id→posts (cas); undone_by→team_members (null) | — | admin, ops, api | client via portal_work; review via get_review_feed,submit_review_seen |

### Scripts (3)

| Table | id (type) | Links to (col→table, on delete) | Linked from | Console (top scripts) | Client page |
|---|---|---|---|---|---|
| video_script_reviews **(dropped)** | id (uuid) | script_id→video_scripts (cas) | — | — | — |
| video_script_scenes | id (uuid) | script_id→video_scripts (cas) | — | scripts | script via get_scripts |
| video_scripts | id (uuid) | client_id→clients (cas); series_id SOFT; created_by SOFT; engagement_id→ops_engagements (null) | ops_task_links, video_script_scenes | scripts, ops, agent | client via portal_work; script via get_scripts; verify via verify_details,verify_details_name… |

### Creators (19)

| Table | id (type) | Links to (col→table, on delete) | Linked from | Console (top scripts) | Client page |
|---|---|---|---|---|---|
| campaign_confirmations | id (uuid) | campaign_id→campaigns (cas); client_id SOFT | — | campaigns, creators | creators via confirm_selection_with,get_campaign |
| campaign_deliverables | id (uuid) | option_id→campaign_options (cas) | — | campaigns, creators, delreq | creator via creator_add_file,creator_remove_file…; creators via get_campaign |
| campaign_options | id (uuid) | campaign_id→campaigns (cas); creator_id→creators (rst) | campaign_deliverables, creator_bill_claims, creator_bills, creator_fees, option_posts, option_qc, option_reviews | campaigns, agent, creators | client via get_portal; creator via creator_add_file,creator_pay_form…; creators via confirm_selection_with,get_campaign… |
| campaigns | id (uuid) | client_id→clients (cas); invoice_claimed_by SOFT | activity_log, campaign_confirmations, campaign_options, links, ops_tasks, push_subscriptions | campaigns, agent, ops | client via get_portal,portal_link_pass; creator via creator_pay_form,creator_post_save…; creators via confirm_selection_with,get_campaign… |
| creator_bill_claims | option_id (uuid) | option_id→campaign_options (cas); claimed_by→team_members (null) | — | campaigns | — |
| creator_bills | bill_id (bigint) | creator_id→creators (cas); option_id→campaign_options (null); made_for→campaign_options (null) | — | campaigns, agent | creator via creator_pay_form |
| creator_earlier_jobs | id (uuid) | creator_id→creators (cas) | — | campaigns, agent | — |
| creator_fees | option_id (uuid) | option_id→campaign_options (cas); set_by→team_members (null) | — | campaigns, agent | — |
| creator_pay_requests | id (uuid) | creator_id→creators (cas); decided_by SOFT; entered_by→team_members (-); prior_id SOFT | creator_sheet_rows | campaigns, agent, admin | creator via creator_pay_address,creator_pay_form… |
| creator_profile_changes | id (uuid) | creator_id→creators (cas); restored_from→creator_profile_changes (null) | creator_profile_changes | campaigns | creator via creator_set_profiles |
| creator_profiles | id (uuid) | creator_id→creators (cas) | — | creators | creator via creator_set_profiles,get_creator; creators via get_campaign |
| creator_sheet_rows | id (uuid) | request_id→creator_pay_requests (cas) | — | settings, campaigns | — |
| creator_sheet_settings | id (int) | updated_by SOFT | — | settings | — |
| creator_standard_fees | creator_id (uuid) | creator_id→creators (cas); set_by→team_members (null) | — | agent, campaigns | — |
| creator_upload_counts | option_id (uuid) | — | — | — | — |
| creators | id (uuid) | — | activity_log, campaign_options, creator_bills, creator_earlier_jobs, creator_pay_requests, creator_profile_changes, creator_profiles, creator_standard_fees, push_subscriptions | campaigns, agent, whatsapp | creator via creator_add_file,creator_pay_address…; creators via confirm_selection_with,get_campaign… |
| option_posts | id (uuid) | option_id→campaign_options (cas) | — | campaigns, creators | creator via creator_post_save,get_creator; creators via get_campaign |
| option_qc | id (uuid) | option_id→campaign_options (cas); team_member_id→team_members (rst) | — | campaigns, ops | — |
| option_reviews | id (uuid) | option_id→campaign_options (cas); undone_by→team_members (-) | — | campaigns, creators | creator via get_creator; creators via get_campaign,review_draft |

### Reports (13)

| Table | id (type) | Links to (col→table, on delete) | Linked from | Console (top scripts) | Client page |
|---|---|---|---|---|---|
| ai_draft_limits | scope (text) | — | — | reports | — |
| ai_drafts | id (uuid) | report_id→sm_reports (null); team_member_id→team_members (null); client_id SOFT; brand_id SOFT; batch_id SOFT; script_id SOFT | analytics_reads | reports, scripts, admin | — |
| analytics_reads | id (uuid) | press_id→ai_drafts (null); created_by→team_members (null) | — | analytics | — |
| brand_analyses | id (uuid) | client_id→clients (cas); press_id SOFT; created_by→team_members (null); confirmed_by→team_members (null) | — | crm, checklists, admin | — |
| report_partner_clients **(dropped)** | client_id (uuid) | partner_id→report_partners (-) | — | — | — |
| report_partners **(dropped)** | id (uuid) | — | — | — | — |
| sm_report_ads | id (uuid) | report_id→sm_reports (cas) | — | reports | — |
| sm_report_audits | id (uuid) | report_id→sm_reports (cas); by_id→team_members (null) | — | reports | — |
| sm_report_platforms | id (uuid) | report_id→sm_reports (cas) | sm_report_posts | reports, ops | — |
| sm_report_post_links | id (uuid) | post_id SOFT; report_id SOFT; task_id SOFT; linked_by SOFT; unlinked_by SOFT | — | reports, ops | — |
| sm_report_posts | id (uuid) | report_id→sm_reports (cas); platform_id→sm_report_platforms (cas) | — | reports, ops | — |
| sm_report_versions | id (uuid) | report_id→sm_reports (cas) | — | reports, delreq, documents | client via portal_report,portal_reports; verify via verify_details,verify_details_name… |
| sm_reports | id (uuid) | client_id→clients (cas); submitted_by→team_members (null); confirmed_by→team_members (null); created_by→team_members (null); reviewer_id→team_members (null); label_client SOFT; brand_id SOFT | ai_drafts, ops_notifications, sm_report_ads, sm_report_audits, sm_report_platforms, sm_report_posts, sm_report_versions | reports, agent, ops | client via portal_report,portal_reports; verify via verify_details,verify_details_name… |

### Documents (10)

| Table | id (type) | Links to (col→table, on delete) | Linked from | Console (top scripts) | Client page |
|---|---|---|---|---|---|
| doc_types | id (text) | — | documents | register, letters, quotes | — |
| document_deletions | id (uuid) | — | — | letters | — |
| documents | id (uuid) | type_id→doc_types [text] (null); client_id→clients (null); member_id→team_members (null); replaces→documents (null); supplier_id→suppliers (null) | documents | letters, suppliers, register | verify via verify_details,verify_details_name… |
| signing_steps | id (uuid) | doc_id SOFT | — | hiring, quotes | careers via careers_doc_open; quote via quote_decline,quote_opened |
| verify_check_totals | (kind, doc_id) composite | doc_id SOFT | — | — | verify via verify_checks_of,verify_serial |
| verify_checks | (kind, doc_id, day, addr_hash) composite | doc_id SOFT | — | — | verify via verify_serial |
| verify_detail_tries | ip (text) | — | — | — | verify via verify_details,verify_details_name |
| verify_name_caller_tries | (serial, ip) composite | — | — | — | verify via verify_details_name |
| verify_name_tries | serial (text) | — | — | — | — |
| verify_tries | ip (text) | — | — | — | verify via verify_file,verify_serial |

### Team/HR (56)

| Table | id (type) | Links to (col→table, on delete) | Linked from | Console (top scripts) | Client page |
|---|---|---|---|---|---|
| departments | key (text) | updated_by SOFT | perf_dept_scores, perf_people, team_members | settings, admin, perf | — |
| handbook_docs | id (uuid) | — | handbook_reads, handbook_versions | handbook, agent, search | — |
| handbook_reads | (member_id, doc_id, version_no) composite | member_id→team_members (cas); doc_id→handbook_docs (cas) | — | handbook, admin, onboard | — |
| handbook_versions | id (uuid) | doc_id→handbook_docs (cas) | — | handbook | — |
| health_checkins | (team_member_id, half) composite | team_member_id→team_members (cas) | — | health, team | — |
| health_consents | team_member_id (uuid) | team_member_id→team_members (cas) | — | health, team | — |
| health_log | id (uuid) | team_member_id→team_members (cas) | — | team | — |
| health_moods | id (uuid) | team_member_id→team_members (cas) | — | health | — |
| health_talks | id (uuid) | team_member_id→team_members (cas); with_id→team_members (cas); closed_by→team_members (null) | — | health, team | — |
| health_wordings | version (integer) | — | — | health | — |
| hiring_candidates | id (uuid) | created_by→team_members (null); removed_by→team_members (null); outcome_by→team_members (null); member_id→team_members (null) | hiring_docs, hiring_events, hiring_interviews, hiring_people, hiring_scores, hiring_sheets | hiring, admin, documents | careers via careers_doc_answer,careers_doc_open…; verify via verify_details,verify_details_name… |
| hiring_doc_codes | id (uuid) | doc_id→hiring_docs (cas) | — | — | careers via careers_doc_answer,careers_doc_open… |
| hiring_doc_pay | doc_id (uuid) | doc_id→hiring_docs (cas); set_by→team_members (null) | — | hiring | careers via careers_doc_answer,careers_doc_open… |
| hiring_doc_wrong_days | (doc_id, day) composite | doc_id→hiring_docs (cas) | — | — | careers via careers_doc_open |
| hiring_docs | id (uuid) | candidate_id→hiring_candidates (cas); replaces SOFT; made_by→team_members (null); sent_by→team_members (null); confirmed_by→team_members (null) | hiring_doc_codes, hiring_doc_pay, hiring_doc_wrong_days | hiring, documents, onboard | careers via careers_doc_answer,careers_doc_open…; verify via verify_details,verify_details_name… |
| hiring_events | id (uuid) | candidate_id→hiring_candidates (cas) | — | hiring | careers via careers_doc_answer,careers_none… |
| hiring_files_gone | path (text) | — | — | hiring | — |
| hiring_interviews | id (uuid) | candidate_id→hiring_candidates (cas); invited_by→team_members (null); approved_by→team_members (null); held_by→team_members (null); missed_by→team_members (null) | — | hiring | careers via careers_none,careers_pick… |
| hiring_people | (candidate_id, team_member_id) composite | candidate_id→hiring_candidates (cas); team_member_id→team_members (cas); added_by→team_members (null) | — | hiring, admin, ops | careers via careers_doc_answer,careers_none… |
| hiring_scorecards | id (uuid) | updated_by→team_members (null) | — | hiring, settings | — |
| hiring_scores | (candidate_id, team_member_id) composite | candidate_id→hiring_candidates (cas); team_member_id→team_members (cas) | — | hiring | — |
| hiring_serials_kept | serial (text) | — | — | — | — |
| hiring_sheets | (candidate_id, team_member_id) composite | candidate_id→hiring_candidates (cas); team_member_id→team_members (cas) | — | hiring | — |
| outstation_geo_turns | id (boolean) | — | — | — | — |
| outstation_photos | id (uuid) | stop_id→outstation_stops (cas); removed_by SOFT | — | outstation | — |
| outstation_ref_months | month (text) | — | — | campaigns, settings | — |
| outstation_stops | id (uuid) | trip_id→outstation_trips (cas); client_id→clients (null); touch_id→client_touches (null) | outstation_photos | outstation | — |
| outstation_trips | id (uuid) | driver_id→team_members (-); companions SOFT | outstation_stops | outstation, team | — |
| perf_attempts | team_member_id (uuid) | team_member_id→team_members (cas) | — | perf, health, hiring | — |
| perf_breaches | id (uuid) | team_member_id→team_members (cas); logged_by→team_members (null); voided_by→team_members (null); client_id SOFT | perf_disputes | perf | — |
| perf_commissions | id (uuid) | team_member_id→team_members (cas); client_id→clients (null); created_by→team_members (null); removed_by→team_members (null) | — | perf | — |
| perf_company | period (date) | entered_by→team_members (null) | — | perf | — |
| perf_deleted | id (uuid) | team_member_id→team_members (cas); deleted_by→team_members (null) | — | perf | verify via verify_details,verify_details_name… |
| perf_dept_scores | (quarter, department) composite | department→departments [text] (-); entered_by→team_members (null) | — | perf, settings, admin | — |
| perf_disputes | id (uuid) | review_id→perf_reviews (cas); breach_id→perf_breaches (null); decided_by→team_members (null) | — | perf | — |
| perf_events | id (uuid) | review_id→perf_reviews (null); team_member_id→team_members (cas); actor_id SOFT | — | perf, admin, register | verify via verify_details,verify_details_name… |
| perf_initiatives | id (uuid) | team_member_id→team_members (cas); decided_by→team_members (null) | — | — | — |
| perf_people | team_member_id (uuid) | team_member_id→team_members (cas); department→departments [text] (-) | — | perf, settings, admin | — |
| perf_recognitions | id (uuid) | giver_id→team_members (cas); team_member_id→team_members (cas); decided_by→team_members (null) | — | perf | — |
| perf_reflections | (team_member_id, period) composite | team_member_id→team_members (cas) | — | — | — |
| perf_reviews | id (uuid) | team_member_id→team_members (cas); reviewer_id→team_members (null); finalised_by→team_members (null) | perf_disputes, perf_events | perf, admin, documents | verify via verify_details,verify_details_name… |
| perf_rewards | (kind, period) composite | confirmed_by→team_members (null) | — | perf | — |
| perf_self_ratings | (team_member_id, period) composite | team_member_id→team_members (cas) | — | perf | — |
| perf_settings | (key, from_period) composite | set_by→team_members (null) | — | perf | — |
| perf_unlocks | token_hash (text) | team_member_id→team_members (cas) | — | perf, health, hiring | — |
| personnel_records | team_member_id (uuid) | team_member_id→team_members (-); requested_by SOFT; superior_id SOFT; updated_by SOFT | — | personnel, bukku, hiring | — |
| personnel_salaries | team_member_id (uuid) | team_member_id→team_members (-); updated_by SOFT | — | personnel | — |
| personnel_settings | key (text) | updated_by SOFT | — | personnel | — |
| team_abroad | id (uuid) | team_member_id→team_members (cas); decided_by→team_members (null) | — | team, admin, ops | — |
| team_invites | id (uuid) | caller_id SOFT | — | team | — |
| team_members | id (uuid) | role→team_roles [text] (-); department→departments [text] (-) | agent_schedules, ai_drafts, analytics_reads, app_settings, billing_entities, brand_analyses, bukku_links, bukku_links_gone, bukku_settings, client_ad_debtors … (+88) | team, admin, perf | all (auth/helper fns) |
| team_notices | id (uuid) | recipients SOFT; sent_by SOFT | — | notice | — |
| team_onboarding | member_id (uuid) | member_id→team_members (cas) | — | onboard, hiring | — |
| team_roles | slug (text) | reports_to→team_roles [text] (null) | team_members, team_roles | team, hiring, settings | — |
| team_welcome | member_id (uuid) | member_id→team_members (cas); dm_id→team_members (null); made_by→team_members (null) | — | hiring, onboard, admin | — |
| welcome_kit | id (integer) | updated_by→team_members (null) | — | onboard, admin, settings | — |

### Ops/My Work (22)

| Table | id (type) | Links to (col→table, on delete) | Linked from | Console (top scripts) | Client page |
|---|---|---|---|---|---|
| meeting_message_template | id (int) | updated_by→team_members (null) | — | ops | — |
| ops_due_requests | id (uuid) | task_id→ops_tasks (cas); asked_by→team_members (-); decider_id→team_members (-); decided_by→team_members (-) | — | ops, agent, team | — |
| ops_engagement_checks | id (uuid) | engagement_id→ops_engagements (cas); owner_id→team_members (-); updated_by→team_members (-) | — | ops, checklists, overview | — |
| ops_engagement_events | id (uuid) | engagement_id→ops_engagements (cas); actor_id→team_members (-) | — | — | — |
| ops_engagements | id (uuid) | client_id→clients (cas); manager_id→team_members (-); meeting_owner_id→team_members (-); created_by→team_members (-) | ops_engagement_checks, ops_engagement_events, ops_month_invoices, ops_tasks, video_scripts | ops, overview, agent | client via portal_meetings |
| ops_kpi_targets **(dropped)** | id (uuid) | created_by→team_members (-) | — | — | — |
| ops_month_invoices | engagement_id (uuid) | engagement_id→ops_engagements (cas); client_id SOFT | — | engage, ops, overview | — |
| ops_notifications | id (uuid) | team_member_id→team_members (cas); task_id→ops_tasks (cas); report_id→sm_reports (cas); notice_id SOFT; script_id SOFT; client_id→clients (cas); supplier_id→suppliers (cas) | — | ops, notice, delreq | careers via careers_doc_answer,careers_none…; client via feedback_submit; creator via creator_pay_submit; details via client_details_submit; feedback via feedback_submit; quote via quote_change_request,quote_decline…; supplier via supplier_form_submit |
| ops_recurring_made | (rule_id, on_date) composite | rule_id→ops_recurring_rules (cas); source_task_id SOFT | — | — | — |
| ops_recurring_rules | id (uuid) | client_id→clients (cas); template_id→ops_task_templates (-); owner_id→team_members (-); source_task_id→ops_tasks (null); created_by→team_members (-) | ops_recurring_made | ops, team | — |
| ops_revisions | id (uuid) | task_id→ops_tasks (cas); requested_by→team_members (-); assigned_to→team_members (-); source_review_id SOFT | — | — | — |
| ops_task_assignees | id (uuid) | task_id→ops_tasks (cas); team_member_id→team_members (-); assigned_by→team_members (-) | — | ops, agent, overview | — |
| ops_task_checklist_items | id (uuid) | task_id→ops_tasks (cas); completed_by→team_members (-) | — | ops, agent, crm | — |
| ops_task_events | id (uuid) | task_id→ops_tasks (cas); actor_id→team_members (-) | — | ops, search, overview | — |
| ops_task_links | id (uuid) | task_id→ops_tasks (cas); created_by→team_members (-); ref_id SOFT; post_id→posts (null); script_id→video_scripts (null) | — | ops, admin, scripts | — |
| ops_task_templates | id (uuid) | workflow_id→ops_workflows (-); default_owner_id→team_members (-) | ops_recurring_rules, ops_tasks, ops_template_variants | ops, settings, team | — |
| ops_tasks | id (uuid) | client_id→clients (null); campaign_id→campaigns (null); batch_id→batches (null); source_id SOFT; parent_task_id→ops_tasks (null); template_id→ops_task_templates (-); workflow_id→ops_workflows (-); created_by→team_members (-); manager_id→team_members (-); engagement_id→ops_engagements (null); rated_by→team_members (-); open_by→team_members (null); result_by→team_members (null); delayed_by SOFT; delayed_report SOFT | feedback_responses, ops_due_requests, ops_notifications, ops_recurring_rules, ops_revisions, ops_task_assignees, ops_task_checklist_items, ops_task_events, ops_task_links, ops_tasks … (+2) | ops, agent, overview | — |
| ops_template_variants | id (uuid) | template_id→ops_task_templates (cas) | — | ops, agent, crm | — |
| ops_video_details | task_id (uuid) | task_id→ops_tasks (cas) | — | ops, agent, crm | — |
| ops_work_sessions | id (uuid) | task_id→ops_tasks (cas); team_member_id→team_members (-); corrected_by→team_members (-) | — | ops | — |
| ops_workflow_stages | id (uuid) | workflow_id→ops_workflows (cas) | — | ops, agent, overview | — |
| ops_workflows | id (uuid) | — | ops_task_templates, ops_tasks, ops_workflow_stages | ops, overview, agent | — |

### Settings/system (23)

| Table | id (type) | Links to (col→table, on delete) | Linked from | Console (top scripts) | Client page |
|---|---|---|---|---|---|
| access_keys | key (text) | — | — | delreq | all (auth/helper fns) |
| activity_log | id (uuid) | ref SOFT; client_id→clients (null); campaign_id→campaigns (null); creator_id→creators (null) | — | crm, settings, quotes | all (auth/helper fns) |
| activity_viewers **(dropped)** | email (text) | — | — | — | — |
| agent_schedules | id (uuid) | team_member_id→team_members (cas); condition_ref SOFT | — | agent | — |
| announcements | id (uuid) | — | — | announce | — |
| app_flags | key (text) | — | — | settings, admin, maintenance | — |
| app_secrets | key (text) | — | — | crm, settings, admin | careers via careers_doc_answer,careers_doc_open; quote via quote_decline,quote_opened…; verify via verify_serial |
| app_settings | (key, from_date) composite | set_by→team_members (null) | — | settings, admin, money | all (auth/helper fns) |
| delete_kinds | kind (text) | — | delete_requests | delreq, ops | — |
| delete_requests | id (uuid) | kind→delete_kinds [text] (-); client_id SOFT; requested_by→team_members (-); decided_by→team_members (-) | — | delreq, ops | — |
| guide_seen | (team_member_id, guide) composite | team_member_id→team_members (-) | — | admin, team | — |
| id_formats | kind (text) | updated_by SOFT | — | settings, campaigns | all (auth/helper fns) |
| job_beats | job (text) | — | — | admin | — |
| link_attempts | (kind, token) composite | — | — | admin, settings | creators via confirm_selection_with,get_campaign…; review via get_review_feed,submit_review_seen |
| link_clicks | (slug, code, day) composite | slug→links [text] (cas) | — | admin, crm | — |
| link_qrs | code (text) | slug→links [text] (cas) | — | admin | — |
| link_tries | (kind, token, ip) composite | — | — | admin, settings | creator via creator_add_file,creator_pay_address…; creators via confirm_selection_with,get_campaign…; review via get_review_feed,submit_review_seen |
| links | slug (text) | client_id→clients (null); campaign_id→campaigns (null) | link_clicks, link_qrs | admin, agent, crm | — |
| public_holidays | day (date) | updated_by→team_members (null) | — | settings, hiring, ops | — |
| push_outbox | id (uuid) | target SOFT | — | — | — |
| push_subscriptions | id (uuid) | team_member_id→team_members (cas); campaign_id→campaigns (cas); creator_id→creators (cas); target SOFT | — | push, team | — |
| rail_orders | member_id (uuid) | member_id→team_members (-) | — | admin, team | — |
| s3_sweeps | id (uuid) | — | — | settings | — |

### Messages (20)

| Table | id (type) | Links to (col→table, on delete) | Linked from | Console (top scripts) | Client page |
|---|---|---|---|---|---|
| client_email_templates | kind (text) | updated_by→team_members (null) | — | mailtpl, docmail | — |
| client_emails | id (uuid) | client_id→clients (null); ref_id SOFT; contact_id→client_contacts (null); sent_by→team_members (null) | — | docmail, agent, quotes | — |
| code_email_template | id (integer) | updated_by SOFT | — | mailtpl | — |
| creator_email_templates | purpose (text) | updated_by SOFT | — | mailtpl | creator via creator_pay_submit |
| creator_emails | id (uuid) | creator_id SOFT; request_id SOFT; option_id SOFT; sent_by SOFT; again_of SOFT | — | whatsapp, agent, campaigns | creator via creator_pay_submit |
| email_templates | id (uuid) | updated_by SOFT | — | mailtpl, whatsapp | — |
| feedback_email_templates | (kind, lang) composite | updated_by→team_members (null) | — | mailtpl, crm | — |
| hiring_email_templates | kind (text) | updated_by SOFT | — | mailtpl, hiring | — |
| invoice_email_template | id (int) | updated_by→team_members (null) | — | mailtpl, invoices | — |
| invoice_emails | id (uuid) | client_id→clients (null); sent_by→team_members (null) | — | agent, whatsapp | — |
| invoice_send_template | id (int) | updated_by→team_members (-) | — | mailtpl, invoices | — |
| mail_boxes | key (text) | — | mail_senders | settings, docmail | careers via careers_read; verify via verify_details,verify_details_name |
| mail_senders | key (text) | box→mail_boxes [text] (-) | — | agent, docmail, settings | careers via careers_read |
| quote_email_templates | (kind, lang) composite | updated_by→team_members (null) | — | mailtpl, quotes | — |
| supplier_email_templates | purpose (text) | updated_by→team_members (null) | — | mailtpl, suppliers | — |
| supplier_emails | id (uuid) | supplier_id→suppliers (null); document_id SOFT; sent_by→team_members (null) | — | suppliers, agent, whatsapp | — |
| system_emails | id (uuid) | candidate_id SOFT; client_id SOFT; sent_by SOFT; ref_id SOFT; again_of SOFT | — | agent, whatsapp | — |
| team_emails | id (uuid) | client_id SOFT; supplier_id SOFT; template_id SOFT; sent_by SOFT | — | agent, crm, suppliers | — |
| wa_outbox | id (uuid) | ref_id SOFT; client_id SOFT; to_id SOFT | — | agent, quotes, whatsapp | creator via creator_pay_submit |
| wa_templates | purpose (text) | — | — | whatsapp, agent, quotes | creator via creator_pay_submit |

### Suppliers and other (2)

| Table | id (type) | Links to (col→table, on delete) | Linked from | Console (top scripts) | Client page |
|---|---|---|---|---|---|
| supplier_forms | id (uuid) | supplier_id→suppliers (cas); created_by→team_members (null); used_by→team_members (null) | — | suppliers, search, agent | supplier via supplier_form_read,supplier_form_submit |
| suppliers | id (uuid) | created_by→team_members (null); approved_by→team_members (null); client_id→clients (null) | documents, ops_notifications, supplier_emails, supplier_forms | suppliers, letters, agent | supplier via supplier_form_read,supplier_form_submit; verify via verify_details,verify_details_name… |

## A.2 Non-uuid links

Total flagged: **206** = 20 matched by name/email/code + 15 Bukku ids + 65 copied actor names + 17 other copied values + 89 uuid without FK. Line numbers are `supabase/schema.sql`.

### A.2.1 Matched in SQL by name, email or code (highest risk)

| table.column | refers to | how matched | evidence |
|---|---|---|---|
| clients.owner :41 | team_members.name (owner_id FK exists, :123198) | name = btrim(owner), fallback when owner_id null; rename trigger rewrites it | earlier quote_website_read :163611 / client_details_read :161385 (superseded :164653, :164260 now call client_rep); client_rep :164091; sm_reports_published_notice :92602; team_members_rename_owner :78618; client_owner_id_stamp :123225 |
| campaigns.owner :831 | team_members.name | lower(btrim(owner)) = name | team_work_held :78402; team_members_rename_owner :78623 |
| quotations.made_by :45614 | team_members.name (made_by_id FK added :167405) | btrim(made_by) = name, backfill | quotations_made_by_id :167418, :167439 |
| activity_log.actor :295 | team_members.name | actor = me.name | personnel_revealed :150951 |
| activity_log.subject :297 | clients.name / team_members.name / campaign title | subject = name | backfill join cl.name = a.subject :91999; personnel_revealed :150951 |
| clients.industry :40 | industries.name (text pk, no FK) | lower(name) = lower(btrim(industry)); rename by name | :95447; industry_save :95502 |
| sm_reports.brand_name :30881 | client_brands.name | lower(btrim) name = | sm_report_snapshot :31453 |
| client_services.tax_code :71867 | tax_codes.code (text pk, no FK) | code = | issue_letter :146249, :146313 |
| ops_tasks.stage_key :4443 | ops_workflow_stages.key (+workflow_id) | key =; also ops_task_events.to_value->>stage_key | ops_timeliness :131115; :167151 |
| campaign_options.earlier_job :103393 | creator_earlier_jobs.ref | ref = | creator_earlier_job_remove :108552; creator_earlier_job_set :103596 |
| team_members.email :199 | auth user (JWT email) — identity | lower(email) = lower(jwt email) | allowed() :126476; build_require :130112 |
| client_contacts.email :182 | auth user (JWT email) — client portal identity | lower(email) = lower(jwt email) | portal_clients :150203; :2609 |
| team_invites.email :67531 | team_members.email | lower = | team_member_seen :79010 |
| hiring_candidates.name :119628 | team_members.name | lower name = (clash refusal) | hiring_make_colleague :129525 |
| team_members.card_slug :23281 | links.slug (shared namespace) | slug = card_slug guard | team_card_slug :51483 |
| team_members.access :1445 | access_keys.key (jsonb keys) | key = section | delete_request_file :165572; allowed() :126490 |
| ops_task_templates.name :4410 | ops_task_templates (seed keyed by name) | name = template | ai_written :40195 |
| hiring_doc_codes.email :124486 | signer email | code row keyed by email | decl :124486 |
| quote_sign_codes.email :91012 | signer email | code row keyed by email | decl :91012 |
| signing_steps.email :120215 | signer email | step keyed by email | decl :120215 |

### A.2.2 External Bukku ids (no local table)

| table.column | refers to | how matched | evidence |
|---|---|---|---|
| quotation_invoices.bukku_id | bukku_docs.doc_id (Bukku) | doc_id = bukku_id | quotation_invoices_of :140258 |
| bukku_links.contact_id | bukku_docs.contact_id (Bukku) | contact_id = | :140120; payment_bills :132318 |
| campaigns.bukku_invoice_id | Bukku invoice | external id | decl :159167 |
| client_ad_debtors.contact_id | Bukku contact | external id | decl :124103 |
| creator_bills.contact_id | Bukku contact (bill_id = Bukku bill, pk) | external id | decl :103414 |
| tax_codes.bukku_id | Bukku tax code | external id (text) | decl :71861 |
| bukku_docs.contact_id | Bukku contact | external id | decl :132194 |
| bukku_docs.doc_id, bukku_links_gone.contact_id, bukku_send_claims.made_contact, bukku_settings.field_client, bukku_settings.field_supplier, bukku_settings.field_creator, bukku_settings.bill_account, creator_bills.bill_id | Bukku contacts, docs, custom fields, accounts | stored id | decl lines :132193, :83965, :157029 … |

### A.2.3 Polymorphic uuid (no FK possible)

| table.column | refers to | how matched | evidence |
|---|---|---|---|
| bukku_links.record_id | clients / suppliers / creators by kind | record_id = client_id etc. (15+ joins) | decl :68367 |
| bukku_links_gone.record_id | as bukku_links.record_id | by kind | decl :83964 |
| bukku_send_claims.record_id | as bukku_links.record_id | by kind | decl :150304 |
| activity_log.ref | any record (by action) | none | decl :91947 |
| ops_tasks.source_id | by source_type | none | decl :4439 |
| ops_task_links.ref_id | by kind | none | decl :16885 |
| wa_outbox.ref_id | by purpose | none | decl :38952 |
| wa_outbox.to_id | contact / member by to_kind | none | decl :40395 |
| system_emails.ref_id | by kind | none | decl :130688 |
| client_emails.ref_id | by kind | none | decl :90131 |
| signing_steps.doc_id | quotations / hiring_docs / documents | none | decl :120212 |
| verify_checks.doc_id | by kind | none | decl :135931 |
| verify_check_totals.doc_id | by kind | none | decl :135941 |
| agent_schedules.condition_ref | by condition | none | decl :113424 |
| push_subscriptions.target | hash of audience+ref (push_target :17563) | computed | decl :17508 |
| push_outbox.target | hash of audience+ref | computed | decl :17525 |

### A.2.4 uuid with a single target but no FK

| refers to | columns (decl line) |
|---|---|
| team_members (30) | bukku_links_gone.sent_by :83968, bukku_send_claims.claimed_by :150306, campaigns.invoice_claimed_by :159169, code_email_template.updated_by :121014, creator_email_templates.updated_by :102366, creator_emails.sent_by :130686, creator_pay_requests.decided_by :102351, creator_sheet_settings.updated_by :104382, departments.updated_by :75957, email_templates.updated_by :93316, hiring_email_templates.updated_by :136835, id_formats.updated_by :102114, industries.updated_by :95426, ops_tasks.delayed_by :96812, outstation_photos.removed_by :155266, outstation_trips.companions :142608, perf_events.actor_id :10352, personnel_records.requested_by :121625, personnel_records.superior_id :121631, personnel_records.updated_by :121634, personnel_salaries.updated_by :121644, personnel_settings.updated_by :121653, sm_report_post_links.linked_by :97108, sm_report_post_links.unlinked_by :97111, system_emails.sent_by :128968, team_emails.sent_by :93336, team_invites.caller_id :67530, team_notices.recipients :36047, team_notices.sent_by :36048, video_scripts.created_by :37390 |
| clients (11) | ai_drafts.client_id :24885, campaign_confirmations.client_id :59297, client_brands.client_id :31430, client_document_deletions.client_id :3561, delete_requests.client_id :126229, ops_month_invoices.client_id :107316, perf_breaches.client_id :52717, sm_reports.label_client :31278, system_emails.client_id :128962, team_emails.client_id :93325, wa_outbox.client_id :38953 |
| same table (4) | creator_emails.again_of :130687, creator_pay_requests.prior_id :144281, hiring_docs.replaces :124437, system_emails.again_of :130689 |
| client_brands (2) | ai_drafts.brand_id :31455, sm_reports.brand_id :31441 |
| video_scripts (2) | ai_drafts.script_id :38046, ops_notifications.script_id :37424 |
| documents / client_documents (2) | client_document_deletions.document_id :3559, supplier_emails.document_id :63391 |
| ops_tasks (2) | ops_recurring_made.source_task_id :20145, sm_report_post_links.task_id :97103 |
| sm_reports (2) | ops_tasks.delayed_report :96815, sm_report_post_links.report_id :97102 |
| batches (1) | ai_drafts.batch_id :35450 |
| billing_entities (1) | billing_entities.orphan_of :88127 |
| ai_drafts (1) | brand_analyses.press_id :41340 |
| client_services (uuid[]) (1) | client_document_deletions.service_ids :3564 |
| client_contacts (1) | client_entities.bill_contact_id :88581 |
| creators (1) | creator_emails.creator_id :102382 |
| creator_pay_requests (1) | creator_emails.request_id :102383 |
| campaign_options (1) | creator_emails.option_id :103409 |
| team_notices (1) | ops_notifications.notice_id :36057 |
| reviews (1) | ops_revisions.source_review_id :4549 |
| clients (deliberate, :24642) (1) | posts.cover_for :24650 |
| quotations (1) | quotation_link_copies.quotation_id :156464 |
| rate_card_versions (1) | quotations.version_id :45606 |
| posts (1) | sm_report_post_links.post_id :97101 |
| hiring_candidates (1) | system_emails.candidate_id :128961 |
| suppliers (1) | team_emails.supplier_id :93326 |
| templates (1) | team_emails.template_id :93327 |
| self-group id (not a link) (1) | video_scripts.series_id :37367 |

### A.2.5 Copied values (snapshot text, not matched back)

| kind | columns |
|---|---|
| Actor name copied from `team_members.name` (65; set as `= me.name` in ~60 assignments) | ai_draft_limits.set_by, announcements.created_by, announcements.updated_by, app_flags.set_by, campaign_deliverables.hidden_by, campaign_options.confirmed_by, campaign_options.changes_by, campaigns.created_by, client_checklists.prepared_name, client_checklists.reviewed_name, client_document_deletions.actor, client_documents.issued_by, client_documents.verified_by, client_documents.voided_by, client_requests.decided_by, client_requests.recorded_by, creator_earlier_jobs.added_by, creator_earlier_jobs.removed_by, creator_profile_changes.actor, creators.created_by, document_deletions.actor, documents.issued_by, documents.voided_by, documents.shared_by, feedback_requests.sent_by_name, feedback_requests.manager_name, handbook_docs.created_by, handbook_versions.created_by, hiring_docs.returned_by, hiring_docs.sealed_by, hiring_docs.voided_by, hiring_events.actor, link_qrs.created_by, links.created_by, meta_links.updated_by, option_posts.entered_by, post_versions.replaced_by, quotation_refs_kept.deleted_by, quotations.removed_by, quotations.no_contact_by, quotations.released_by, quotations.submitted_by, quotations.reviewer_name, quotations.reviewed_by, quotations.returned_by, quotations.sealed_by, quotations.withdrawn_by, quotations.confirmed_by, quotations.details_asked_by, rate_card_text.updated_by, rate_card_versions.published_by, sm_report_audits.by_name, sm_report_versions.published_by, sm_report_versions.withdrawn_by, sm_report_versions.file_by, sm_reports.sent_by, team_notices.sent_by_name, team_notices.withdrawn_by, video_script_scenes.shot_by, video_script_scenes.photo_by, video_scripts.vo_shot_by, video_scripts.created_by_name, video_scripts.updated_by_name, wa_outbox.created_by, wa_templates.set_by |
| Other copied names, titles, codes (17) | bukku_docs.contact_name :132195, bukku_links.person :87360, campaign_confirmations.person :897, campaign_confirmations.campaign_title :59296, campaign_options.visit_pic :1341, client_documents.client_code :3053, client_requests.contact_name :2147, client_touches.contact_name :145, feedback_requests.sent_to_name :147083, feedback_responses.contact_name :147109, invoice_emails.client_name :82656, ops_notifications.from_name :36058, quotations.brand :45604, system_emails.to_name :128964, team_emails.to_name :93329, video_scripts.cast_names :37378, wa_outbox.to_name :38947 |

## A.3 Orphans and oddities

- **Dropped but still in the 211**: activity_viewers, ops_kpi_targets, report_partner_clients, report_partners, video_script_reviews (created, then `drop table` at :78864–78868). `report_partner_save` still names `report_partner_clients` (dead function).
- **No uuid key (65)**: settings and template tables keyed on text (`app_settings`, `id_formats`, `*_email_templates`, `tax_codes`, `services`, `team_roles`, `departments`, `industries`, `links`), rate-limit tables keyed on ip/token (`*_tries`, `*_hits`, `link_attempts`), Bukku mirrors on composite keys (`bukku_docs`, `bukku_links`), `creator_bills` (Bukku bill id). `bukku_links_gone` has **no primary key at all**; `outstation_geo_turns` keys on a boolean (single-row table).
- **Name-keyed master tables**: `industries` (pk `name`) is matched from `clients.industry` with no FK, so a rename is carried by `industry_save` alone (:95502); `tax_codes` (pk `code`) has no FK from `client_services.tax_code`.
- **Owner by name while a uuid exists**: `clients.owner_id` (:123198) and `quotations.made_by_id` (:167405) were added beside the name columns. `client_rep` (:164084, used by the latest `/quote/` and `/details/` reads) takes `owner_id` first but still falls back to matching `clients.owner` to `team_members.name` (:164091); `campaigns.owner` has no uuid at all and is kept in step only by the rename trigger (:78623).
- **Identity by email**: `team_members` holds no auth user id; every `allowed()` check resolves the caller by `lower(email)` against the JWT (:126476). `client_contacts.email` is the client portal's identity the same way (:150203).
- **FKs with no `on delete` (47)**: 36 to `team_members` (`ops_*` actors, `clients.vic_by`, `clients.sales_by`, `delete_requests.*`, `personnel_*`, `outstation_trips.driver_id`) block a hard delete of a colleague (members are soft-removed, `erased_at`); `client_services.quotation_id` blocks a quotation delete; `ops_tasks.template_id/workflow_id` block template removal.
- **Function-only tables** (no `.from` in `js/`, no inbound FK, reached only through functions or an edge function): bukku_send_claims, client_document_seq, creator_upload_counts, hiring_serials_kept, ops_engagement_events, ops_recurring_made, ops_revisions, outstation_geo_turns, perf_initiatives, perf_reflections, push_outbox (`supabase/functions/push-send`), verify_name_tries. None is unreachable.
- **Self-group uuid**: `video_scripts.series_id` is a generated group id (unique with `video_no`), not a link; `posts.cover_for` has no FK by design (comment :24642).

## C. Agency values

Scope: every text file in the repo except `.git/`, `tests/`, `node_modules/`, `.claude/`, `drafts/`, `docs/DECISIONS.md`, `docs/DESIGN-NOTES.md`. **Excluded (user's root Jotform pages, not scanned): `ap01.html`, `accv-new.html`.** Binary files (images, fonts) not scanned. "code" = outside a comment; "cmt" = inside a JS/CSS/HTML/SQL comment or in a `.md` file (heuristic masking; regex literals containing `/*` may misclassify a handful). Counts are regex matches, not distinct values. Secrets: the Supabase anon key sits at `js/config.js:52`, the Google browser key at `js/config.js:124`, the Turnstile site key at `js/config.js:162` (all public by design; not copied here).

### C.1 Already central

| Store | Defined | Holds | Read by |
|---|---|---|---|
| `window.ADSPACE_ORG` | `js/config.js:14–45` | legal name `ADSPACE PLT`, regno, SST no., address, email, phone, website, `map` (hi.adspace.me/map), bank (blank), `ap01`, letterhead `logo` (`/css/adspace-mark.png`), PDF fonts (`SlateBook`, `SlateRg`, `OPTIMA`, `SlateMedium`, Noto CJK), `verifyUrl` | `documents.js` (×5 incl. logo/fonts), `letters.js`, `quotepdf.js`, `hrdocs.js`, `hiring.js`, `careers.js`, `card.js`, `namecard.js`, `feedback.js`, `ops.js`, `perf.js`, `portal.js`, `verify.js`, `demo.js`; `verifyUrl` also by `quotes.js`, `seal.js` |
| `ADSPACE_CONFIG.agencyName` | `js/config.js:127` (`'ADspace'`) | trading name | `quotepdf.js:27`, `documents.js:30`, `seal.js:100`, `creator.js:43`, `namecard.js:19,55`, `verify.js:83`, `quotes.js:1358` (→ `quotation_words_keep`), `demo.js:99` |
| `ADSPACE_CONFIG.brandLogo` | `js/config.js:126` (mycdn.adspace.me/adspace-brandname.png) | header wordmark | `chrome.js:162`, `maintenance.js:134`, `documents.js:697` (fallback to ORG.logo), `demo.js:98` |
| `ADSPACE_CONFIG.serviceTermsUrl` | `js/config.js:130` (hi.adspace.me/svc-terms) | Service Terms URL | `quotepdf.js:30`, `quote.js:1708`, `quotes.js:1358`, `demo.js:100` |
| `ADSPACE_CONFIG.supportEmail` / `accountEmail` | `js/config.js:131,134` | advertise@ mailbox | `portal.js` (accountEmail), `demo.js`; no other reader |
| `ADSPACE_CONFIG.linkHost` | `js/config.js:140` | hi.adspace.me | `admin.js`, `crm.js`, `namecard.js`, `team.js` |
| `ADSPACE_CONFIG.socialLinks` / `quoteWhatsApp` | `js/config.js:165–171` | FB / IG / LinkedIn, wa.me/adspace | `feedback.js`; `quote.js`, `careers.js`, `card.js`, `maintenance.js` |
| `ADSPACE_CONFIG.supabaseUrl`, `mediaCookieDomain`, `verify.page` | `js/config.js:51,107,…` | project ref URL, `adspace.me`, verify page | `api.js`, `maintenance.js`, `index.html`; `media.js`; documents/quotes |
| `mail_boxes` | `schema.sql:128873–128886` (+ `hr` 134150, `legal` 135205); migration `2026-11-17-every-email-in-messages.sql:43–46` | 6 reply-to mailboxes @adspacestudios.com | `mail_sender()` → `_shared/mail.ts:160 sender()` → invite-member, bukku-sync, hiring-mail, supplier-mail; `mail_senders_read`, `mail_log` |
| `mail_senders` | `schema.sql:128888–128904`; same migration `:59–64`; `portal@sc.adspace.me` 130649 / `2026-11-18-portal-sender.sql:24` | sender names (`ADspace`, `ADspace Finance`, `ADspace Digital Portal`) + noreply-*@sc.adspace.me | as above |
| `id_formats` | `schema.sql:102107–102120` | numbering prefixes | holds **no** agency value |

Gaps: no server-side store for legal name, regno, address, phone, domain or logo (edge functions, SQL templates and workers type them); no store for CSS/page font preloads (CSS `@font-face` in `css/portal.css:201–382` is the de-facto one); no store for the S3 bucket/region outside each consumer.

### C.2 Bypasses

A literal typed in code although a central store holds the same value.

| Group | Count | Where (top) |
|---|---|---|
| Client side (pages, js, PDFs, css, manifests): literal with a client store | **471** | name 363, domain 53, legal name 24, social 12, mailbox 8, address 8, logo 3. Top files: `js/quote.js` 78, `index.html` 52, `js/careers.js` 31, `admin/index.html` 27, `js/creator.js` 24, `js/verify.js` 19, `js/words.js` 18, `js/supplierform.js` 12, `404.html` 10, `card/index.html` 10; every portal page head types `ADspace` ×3–5 (title, og:site_name, og:title, description) |
| Server side: mailbox literal bypassing `mail_boxes` | **20** | `schema.sql:1481` (admin login), 2540 (`%@adspacestudios.com` filter), 82696, 83670 (einvoice@ in reminder templates), 102374, 126645–126646 (hr@, management@ — not in store), 144577×2; mirrored in 7 migrations (8 hits); `push-send/index.ts:23` (VAPID subject); `_shared/mail.ts:165` ×2 (fallback after `sender()`) |
| **Bypass total** | **491** | |
| Literal fallbacks after reading the store (`cfg.agencyName \|\| 'ADspace'`) | 24 | name 12, domain 6, legal name 3, social 3 — e.g. `letters.js:346`, `documents.js:812`, `hrdocs.js:261`, `admin.js:2359,8334`, `careers.js:87,433` |
| Server literals with **no** store | 437 | name 270, domain 93, legal name 21, address 18, cloud id 15, social 10, regno 5, phone 3, logo 2 — e.g. `_shared/mail.ts:63–75` (email foot: legal name, regno, address, phone, wordmark), `hiring-mail/index.ts:96–98`, `workers/links/worker.js:270` |

Notable single bypasses: `js/chrome.js:122–123` (every client page's foot: `ADSPACE PLT`, adspacestudios.com/legal/policies); `js/supplierform.js:40–44` (legal name ×6 in the mandate); `js/creator.js:535–537,776` (own social URLs incl. tiktok.com/@adspace.advertising, not in `socialLinks`); `js/campaigns.js:163` (IG placeholder); `js/smreport.js:182,1886` (hi.adspace.me/fb-ad-terms); `admin/index.html:6041,6070` (postcode); `index.html:58–212` (JSON-LD + links: mailbox ×3, adspacestudios.com ×11, wa.me ×3, maps.app.goo.gl ×2); `workers/video-convert/index.mjs:122` and `.github/workflows/db-backup.yml:35–36` (bucket `myadspace`, `ap-southeast-5`).

### C.3 By area

Status: DEFINITION = the central store itself; BYPASS = literal though a store exists; reads central + literal fallback; no store / no server store; comment only; fixture (demo data).

### portal pages

| file:lines | kind | n (code/cmt) | values | central? |
|---|---|---|---|---|
| 404.html:32,62,73,86 | domain | 3/1 | adspacestudios.com×3, mycdn.adspace.me | BYPASS |
| 404.html:16 | font | 1/0 | SlateRg | no store |
| 404.html:85 | legal name | 1/0 | ADSPACE PLT | BYPASS |
| 404.html:62 | logo/wordmark | 1/0 | adspace-brandname | BYPASS |
| 404.html:74 | mailbox | 1/0 | advertise@adspacestudios.com | BYPASS |
| 404.html:12,62,63,71 | name | 4/0 | ADspace×4 | BYPASS |
| admin/index.html:6041,6070 | address | 2/0 | 81100 Johor×2 | BYPASS |
| admin/index.html:11–6505 | domain | 9/0 | adspace.me×7, digital.adspace.me, hi.adspace.me | BYPASS |
| admin/index.html:99 | font | 1/0 | SlateRg | no store |
| admin/index.html:1253,6630,6631,6676 | mailbox | 4/0 | portal@sc.adspace.me×2, accounts@adspace.me, ap@adspacestudios.com | BYPASS |
| admin/index.html:201–6483 | mailbox placeholder | 7/0 | email@adspace.me×5, email@adspacestudios.com×2 | no store |
| admin/index.html:7–6676 | name | 13/2 | ADspace×15 | BYPASS (1 fallback) |
| admin/offline.html:78 | domain | 1/0 | adspacestudios.com | BYPASS |
| admin/offline.html:44 | font | 1/0 | Slate | no store |
| admin/offline.html:78 | legal name | 1/0 | ADSPACE PLT | BYPASS |
| admin/offline.html:44,69 | name | 2/0 | ADspace×2 | BYPASS |
| card/index.html:13,58 | domain | 2/0 | digital.adspace.me, adspacestudios.com | BYPASS |
| card/index.html:22,23 | font | 2/0 | SlateRg, OPTIMA | no store |
| card/index.html:8–59 | name | 7/0 | ADspace×6, adspace | BYPASS |
| card/index.html:59 | social/map URL | 1/0 | wa.me/adspace | BYPASS |
| careers/index.html:16 | font | 1/0 | SlateRg | no store |
| careers/index.html:8,9,10,11,12 | name | 5/0 | ADspace×5 | BYPASS |
| client/index.html:19 | font | 1/0 | SlateRg | no store |
| client/index.html:71 | mailbox placeholder | 1/0 | email@adspace.me | no store |
| client/index.html:8,9,10,11,12,130 | name | 5/1 | ADspace×6 | BYPASS |
| creator/index.html:19 | font | 1/0 | SlateRg | no store |
| creator/index.html:8,9,10,11 | name | 4/0 | ADspace×4 | BYPASS |
| creators/index.html:22 | font | 1/0 | SlateRg | no store |
| creators/index.html:8,10,11 | name | 3/0 | ADspace×3 | BYPASS |
| details/index.html:16 | font | 1/0 | SlateRg | no store |
| details/index.html:8,9,10,11,12 | name | 5/0 | ADspace×5 | BYPASS |
| docs/PAGE-TEMPLATE.html:40 | domain | 1/0 | digital.adspace.me | BYPASS |
| docs/PAGE-TEMPLATE.html:48 | font | 1/0 | SlateRg | no store |
| docs/PAGE-TEMPLATE.html:2,36,38,43 | name | 3/1 | ADspace×4 | BYPASS |
| feedback/index.html:16 | font | 1/0 | SlateRg | no store |
| feedback/index.html:8,9,10,11,12 | name | 5/0 | ADspace×5 | BYPASS |
| index.html:92,201 | address | 5/0 | Mutiara Emas×2, Mount Austin×2, 81100 Johor | BYPASS |
| index.html:12–163 | domain | 21/1 | adspacestudios.com×11, digital.adspace.me×9, mycdn.adspace.me×2 | BYPASS |
| index.html:18,43 | font | 1/1 | Optima, SlateRg | no store |
| index.html:60 | legal name | 1/0 | ADSPACE PLT | BYPASS |
| index.html:62,86 | logo/wordmark | 2/0 | adspace-brandname×2 | BYPASS |
| index.html:65,72,87 | mailbox | 3/0 | advertise@adspacestudios.com×3 | BYPASS |
| index.html:12–212 | name | 15/4 | ADspace×16, adspace×3 | BYPASS |
| index.html:73,89,131,202,212 | social/map URL | 5/0 | wa.me/adspace×3, maps.app.goo.gl×2 | BYPASS |
| quote/index.html:16 | font | 1/0 | SlateRg | no store |
| quote/index.html:8,9,10,11,12 | name | 5/0 | ADspace×5 | BYPASS |
| review/index.html:32 | font | 1/0 | SlateRg | no store |
| review/index.html:8,17,19,20,23,25 | name | 5/2 | ADspace×7 | BYPASS |
| script/index.html:22 | font | 1/0 | SlateRg | no store |
| script/index.html:8,12,14,15,18 | name | 5/0 | ADspace×5 | BYPASS |
| supplier-details/index.html:7 | name | 1/0 | ADspace | BYPASS |
| supplier/index.html:16 | font | 1/0 | SlateRg | no store |
| supplier/index.html:8,9,10,11,12 | name | 5/0 | ADspace×5 | BYPASS |
| verify/index.html:12 | font | 1/0 | SlateRg | no store |
| verify/index.html:8,9,10,11 | name | 4/0 | ADspace×4 | BYPASS |

### js

| file:lines | kind | n (code/cmt) | values | central? |
|---|---|---|---|---|
| js/admin.js:2359–8929 | domain | 3/7 | hi.adspace.me×4, go.adspace.me×4, digital.adspace.me | BYPASS (2 fallback) |
| js/admin.js:6785 | legal name | 0/1 | ADSPACE PLT | comment only |
| js/admin.js:572,2361,2826 | name | 3/0 | ADspace×2, adspace | BYPASS |
| js/agent.js:1 | name | 0/1 | ADspace | comment only |
| js/analytics.js:1056,1066 | name | 2/0 | ADspace×2 | BYPASS |
| js/announce.js:356 | domain | 1/0 | adspace.me | BYPASS |
| js/api.js:369 | phone | 0/2 | 60187625233, 762 5233 | comment only |
| js/campaigns.js:2067,2736 | domain | 0/2 | hi.adspace.me×2 | comment only |
| js/campaigns.js:163 | social/map URL | 1/0 | instagram.com/adspace.advertising | BYPASS |
| js/captcha.js:1 | name | 0/1 | ADspace | comment only |
| js/card.js:48,50 | name | 1/1 | ADspace×2 | BYPASS |
| js/careers.js:24–457 | name | 33/7 | ADspace×38, adspace×2 | BYPASS (2 fallback) |
| js/careers.js:87,433 | social/map URL | 2/0 | wa.me/adspace×2 | reads central + literal fallback |
| js/chart.js:1 | name | 0/1 | ADspace | comment only |
| js/checklists.js:1 | name | 0/1 | ADspace | comment only |
| js/chrome.js:123 | domain | 1/0 | adspacestudios.com | BYPASS |
| js/chrome.js:122 | legal name | 1/0 | ADSPACE PLT | BYPASS |
| js/chrome.js:2,5,70,83,100,101 | name | 3/3 | ADspace×6 | BYPASS |
| js/config.js:18 | address | 3/0 | Mutiara Emas, Mount Austin, 81100 Johor | DEFINITION (central) |
| js/config.js:51 | cloud id | 1/0 | hwwuigvdfubuymchsvyx | DEFINITION (central) |
| js/config.js:21–140 | domain | 6/4 | hi.adspace.me×3, digital.adspace.me×2, mycdn.adspace.me×2 | DEFINITION (central) |
| js/config.js:30–42 | font | 4/5 | Slate×4, Optima, SlateBook | DEFINITION (central) |
| js/config.js:15 | legal name | 1/0 | ADSPACE PLT | DEFINITION (central) |
| js/config.js:34,126 | logo/wordmark | 2/0 | adspace-mark, adspace-brandname | DEFINITION (central) |
| js/config.js:19,131,134 | mailbox | 3/0 | advertise@adspacestudios.com×3 | DEFINITION (central) |
| js/config.js:2,127,171 | name | 2/1 | ADspace×2, adspace | DEFINITION (central) |
| js/config.js:20 | phone | 1/0 | 60187625233 | DEFINITION (central) |
| js/config.js:16 | registration | 1/0 | 202304002162 | DEFINITION (central) |
| js/config.js:166,167,168,171 | social/map URL | 4/0 | facebook.com/adspacestudios, instagram.com/adspace.advertising, linkedin.com/company/adspacestudios | DEFINITION (central) |
| js/config.js:17 | tax number | 1/0 | J31-2401-32100002 | DEFINITION (central) |
| js/creator.js:127,236 | legal name | 2/0 | ADSPACE PLT×2 | BYPASS |
| js/creator.js:1265 | mailbox placeholder | 1/0 | email@adspace.me | no store |
| js/creator.js:43–253 | name | 19/0 | ADspace×19 | BYPASS (1 fallback) |
| js/creator.js:535,536,537,776 | social/map URL | 4/0 | instagram.com/adspace.advertising, tiktok.com/@adspace.advertising, facebook.com/adspace.advertising | BYPASS |
| js/creators.js:169–477 | name | 7/0 | ADspace×7 | BYPASS |
| js/crm.js:3113 | domain | 1/0 | hi.adspace.me | reads central + literal fallback |
| js/crm.js:4700–8027 | name | 8/1 | ADspace×6, adspace×3 | BYPASS |
| js/demo.js:110 | address | 1/0 | 81100 Johor | BYPASS |
| js/demo.js:299 | name | 2/0 | ADspace×2 | BYPASS |
| js/details.js:135 | mailbox placeholder | 1/0 | email@adspace.me | no store |
| js/details.js:25,33,35,47,54,55 | name | 6/0 | ADspace×6 | BYPASS |
| js/feedback.js:23,25,26,32,33,70 | name | 5/1 | ADspace×6 | BYPASS |
| js/form.js:451 | legal name | 0/1 | ADSPACE PLT | comment only |
| js/handbook.js:356 | name | 2/0 | ADspace×2 | BYPASS |
| js/health.js:145 | name | 0/1 | ADspace | comment only |
| js/hiring.js:1127 | legal name | 1/0 | ADSPACE PLT | reads central + literal fallback |
| js/hiring.js:810 | mailbox placeholder | 1/0 | email@adspacestudios.com | no store |
| js/hiring.js:482,483,616,1053 | name | 5/0 | ADspace×5 | BYPASS |
| js/hrdocs.js:261,309 | legal name | 2/0 | ADSPACE PLT×2 | BYPASS |
| js/hrdocs.js:102,103,224,246,271 | name | 5/0 | ADspace×5 | BYPASS |
| js/hrforms.js:145,149 | name | 2/1 | ADSPACE×3 | BYPASS |
| js/icons.js:1,369,370 | name | 0/3 | ADspace×3 | comment only |
| js/invoices.js:464 | name | 1/0 | ADspace | BYPASS |
| js/maintenance.js:131,138 | name | 3/0 | ADspace×2, adspace | BYPASS (1 fallback) |
| js/maintenance.js:131 | social/map URL | 1/0 | wa.me/adspace | reads central + literal fallback |
| js/media.js:53,86,161 | domain | 0/4 | adspace.me×3, mycdn.adspace.me | comment only |
| js/media.js:13,62,112 | name | 3/0 | adspace×3 | BYPASS |
| js/menu.js:254 | name | 1/0 | ADspace | BYPASS |
| js/money.js:10 | name | 0/1 | ADspace | comment only |
| js/namecard.js:46,241 | domain | 2/0 | hi.adspace.me×2 | reads central + literal fallback |
| js/namecard.js:5,6,152 | font | 0/3 | Optima×2, Slate | comment only |
| js/namecard.js:5,19,55,69,152 | name | 3/2 | ADspace×5 | BYPASS (2 fallback) |
| js/onboard.js:114 | name | 2/0 | ADspace×2 | BYPASS |
| js/ops.js:196,3694,5910,6509 | name | 4/0 | ADspace×4 | BYPASS |
| js/outstation.js:934 | name | 1/0 | ADspace | BYPASS |
| js/passkey.js:6 | domain | 0/1 | digital.adspace.me | comment only |
| js/perf.js:2190 | domain | 1/0 | digital.adspace.me | reads central + literal fallback |
| js/personnel.js:573 | legal name | 1/0 | ADSPACE PLT | BYPASS |
| js/personnel.js:159,160,161 | name | 3/0 | ADspace×3 | BYPASS |
| js/portal.js:64–1330 | name | 6/3 | ADspace×9 | BYPASS |
| js/push-sw.js:20 | name | 1/0 | ADspace | BYPASS |
| js/quote.js:905 | domain | 1/0 | adspace.me | BYPASS |
| js/quote.js:928,1689 | mailbox placeholder | 2/0 | email@adspace.me×2 | no store |
| js/quote.js:47–2219 | name | 76/3 | ADspace×74, adspace×4, ADSPACE | BYPASS |
| js/quote.js:1294 | social/map URL | 1/0 | wa.me/adspace | BYPASS |
| js/quotes.js:1,1358 | name | 1/1 | ADspace×2 | reads central + literal fallback |
| js/records.js:1 | name | 0/1 | ADspace | comment only |
| js/refresh.js:1 | name | 0/1 | ADspace | comment only |
| js/register.js:119,234,251,388 | name | 1/4 | ADspace×4, ADSPACE | BYPASS |
| js/reports.js:622,633,4585 | name | 2/1 | ADspace×2, adspace | BYPASS |
| js/review.js:1129 | domain | 0/1 | hi.adspace.me | comment only |
| js/review.js:1403 | name | 1/0 | ADspace | BYPASS |
| js/script.js:313 | name | 1/0 | ADspace | BYPASS |
| js/scripts.js:1317 | domain | 0/1 | hi.adspace.me | comment only |
| js/settings.js:507,981,987 | name | 2/1 | ADspace×3 | BYPASS |
| js/supplierform.js:40,41,42,43,44 | legal name | 6/0 | ADSPACE PLT×6 | BYPASS |
| js/supplierform.js:123,133 | mailbox placeholder | 2/0 | email@adspace.me×2 | no store |
| js/supplierform.js:95,103,127,160 | name | 6/0 | ADspace×6 | BYPASS |
| js/swipe.js:1 | name | 0/1 | ADspace | comment only |
| js/verify.js:4–129 | legal name | 6/1 | ADSPACE PLT×7 | BYPASS (1 fallback) |
| js/verify.js:26–87 | name | 15/1 | ADspace×16 | BYPASS (1 fallback) |
| js/whatsapp.js:38,41,43,1135 | domain | 3/1 | digital.adspace.me×3, hi.adspace.me | BYPASS |
| js/whatsapp.js:110,1604 | name | 2/0 | ADspace, adspace | BYPASS |
| js/words.js:519 | legal name | 0/1 | ADSPACE PLT | comment only |
| js/words.js:27–220 | name | 18/1 | ADspace×19 | BYPASS |

### PDFs

| file:lines | kind | n (code/cmt) | values | central? |
|---|---|---|---|---|
| js/documents.js:495,663 | domain | 2/0 | digital.adspace.me×2 | BYPASS |
| js/documents.js:400–993 | font | 0/12 | Slate×11, Optima | comment only |
| js/documents.js:543,802,812,1207,1342,1345 | legal name | 3/3 | ADSPACE PLT×6 | BYPASS |
| js/documents.js:13–1348 | name | 4/3 | ADspace×7 | BYPASS (1 fallback) |
| js/documents.js:699 | phone | 0/2 | 762 5233, 60187625233 | comment only |
| js/letters.js:346 | legal name | 1/0 | ADSPACE PLT | BYPASS |
| js/quotepdf.js:251 | font | 0/1 | Slate | comment only |
| js/quotepdf.js:15,28 | legal name | 1/1 | ADSPACE PLT×2 | reads central + literal fallback |
| js/quotepdf.js:27 | name | 1/0 | ADspace | reads central + literal fallback |
| js/ratecardpdf.js:7 | font | 0/1 | Optima | comment only |
| js/ratecardpdf.js:48 | name | 1/0 | ADspace | BYPASS |
| js/scriptpdf.js:10,181 | font | 0/2 | Slate×2 | comment only |
| js/seal.js:100 | name | 1/0 | ADspace | reads central + literal fallback |
| js/smreport.js:182,1886 | domain | 3/0 | hi.adspace.me×3 | BYPASS |
| js/smreport.js:17–2072 | font | 0/13 | Slate×12, Optima | comment only |
| js/smreport.js:28,33,2344 | name | 0/3 | ADspace×3 | comment only |

### css

| file:lines | kind | n (code/cmt) | values | central? |
|---|---|---|---|---|
| css/console.css:5217,8320 | font | 4/0 | Optima×4 | no store |
| css/console.css:1,5217,8320 | name | 2/1 | ADspace×3 | BYPASS |
| css/portal.css:5477 | domain | 0/1 | adspacestudios.com | comment only |
| css/portal.css:201–5745 | font | 16/6 | Slate×9, Optima×9, SlateRg×2 | no store |
| css/portal.css:1–7107 | name | 7/4 | ADspace×11 | BYPASS |

### emails & edge fns

| file:lines | kind | n (code/cmt) | values | central? |
|---|---|---|---|---|
| js/mailtpl.js:52,53 | name | 3/0 | ADspace×3 | no server store |
| supabase/functions/_shared/cors.ts:13 | domain | 1/0 | digital.adspace.me | no server store |
| supabase/functions/_shared/mail.ts:69 | address | 3/0 | Mutiara Emas, Mount Austin, 81100 Johor | no server store |
| supabase/functions/_shared/mail.ts:42,63,70 | domain | 5/0 | adspace.me×3, digital.adspace.me, mycdn.adspace.me | no server store |
| supabase/functions/_shared/mail.ts:69,75 | legal name | 2/0 | ADSPACE PLT×2 | no server store |
| supabase/functions/_shared/mail.ts:63 | logo/wordmark | 1/0 | adspace-brandname | no server store |
| supabase/functions/_shared/mail.ts:150,165 | mailbox | 2/1 | portal@sc.adspace.me×2, advertise@adspacestudios.com | BYPASS of mail_boxes |
| supabase/functions/_shared/mail.ts:63,124,165 | name | 3/0 | ADspace×3 | no server store |
| supabase/functions/_shared/mail.ts:70 | phone | 1/0 | 762 5233 | no server store |
| supabase/functions/_shared/mail.ts:69 | registration | 1/0 | 202304002162 | no server store |
| supabase/functions/analytics-read/index.ts:55,77 | name | 2/0 | ADspace×2 | no server store |
| supabase/functions/brand-analysis/index.ts:170,185,197,211,229 | name | 5/0 | ADspace×5 | no server store |
| supabase/functions/caption-draft/index.ts:44,66 | name | 2/0 | ADspace×2 | no server store |
| supabase/functions/checklist-draft/index.ts:74,122 | name | 2/0 | ADspace×2 | no server store |
| supabase/functions/creator-mail/index.ts:42,55 | domain | 1/1 | digital.adspace.me×2 | no server store |
| supabase/functions/hiring-mail/index.ts:97 | address | 3/0 | Mutiara Emas, Mount Austin, 81100 Johor | no server store |
| supabase/functions/hiring-mail/index.ts:96,98 | domain | 2/0 | digital.adspace.me, hi.adspace.me | no server store |
| supabase/functions/hiring-mail/index.ts:34 | legal name | 0/1 | ADSPACE PLT | comment only |
| supabase/functions/hiring-mail/index.ts:17,41,104,105,130,143 | name | 2/5 | ADspace×7 | no server store |
| supabase/functions/invite-member/index.ts:31,32 | domain | 2/0 | digital.adspace.me×2 | no server store |
| supabase/functions/invite-member/index.ts:45–171 | name | 11/1 | ADspace×12 | no server store |
| supabase/functions/media-pass/index.ts:10,11,46 | domain | 1/2 | mycdn.adspace.me×2, adspace.me | no server store |
| supabase/functions/meet-create/index.ts:3 | mailbox | 0/1 | adspacestudios@gmail.com | comment only |
| supabase/functions/meet-create/index.ts:2,204 | name | 1/1 | ADspace×2 | no server store |
| supabase/functions/meta-import/index.ts:4,6 | name | 0/2 | ADspace×2 | comment only |
| supabase/functions/portal-agent/index.ts:65 | name | 2/0 | ADspace×2 | no server store |
| supabase/functions/push-send/index.ts:23 | mailbox | 1/0 | advertise@adspacestudios.com | BYPASS of mail_boxes |
| supabase/functions/push-send/index.ts:77 | name | 1/0 | ADspace | no server store |
| supabase/functions/report-draft/index.ts:160,196,222,247 | name | 4/0 | ADspace×4 | no server store |
| supabase/functions/script-draft/index.ts:78,107,153 | name | 3/0 | ADspace×3 | no server store |
| supabase/functions/sign-download/index.ts:42,92 | domain | 1/1 | mycdn.adspace.me×2 | no server store |
| supabase/functions/sign-download/index.ts:2,28,246 | name | 0/3 | ADspace×3 | comment only |
| supabase/functions/sign-upload/index.ts:3 | name | 0/1 | ADspace | comment only |
| supabase/functions/supplier-mail/index.ts:318 | domain | 1/0 | digital.adspace.me | no server store |
| supabase/functions/supplier-mail/index.ts:182,184,234,329,359 | name | 4/1 | ADspace×5 | no server store |


### schema & migrations (`supabase/schema.sql` + 134 of 766 migrations hit)

Migrations mirror schema sections, so most values appear twice.

| kind | schema.sql code/cmt | migrations code/cmt | representative lines (schema.sql) | central? |
|---|---|---|---|---|
| name `ADspace` | 111/65 | 111/64 | 2437–2439 (rate-card lines), 63381, 90118–90122, 92768 (email subjects `… · ADspace`), 92703 (signing code), 66911 | no server store; senders' names in `mail_senders` 128898–128903 = DEFINITION |
| legal name | 10/27 | 9/30 | 66071 (agreement template), 126642 (HR onboarding block) | no server store |
| registration | 2/0 | 2/0 | 66071, 126642 | no server store |
| address | 6/0 | 6/0 | 66071, 126643 | no server store |
| phone | 1/0 | 1/0 | 126645 | no server store |
| domain | 36/25 | 38/24 | digital.adspace.me ×28 (links in templates), go.adspace.me ×5, hi.adspace.me ×3 | no server store |
| mailbox | 22/6 | 21/5 | store rows 128882–128903, 130649, 134150, 135205 (DEFINITION); bypasses listed in C.2 | mail_boxes / mail_senders |
| mailbox placeholder | 0/1 | — | | — |
| social/map | 5/4 | 5/4 | 140877, 140884 (wa.me/adspace in interview templates), 141202–141207 (Short Link seed + replace) | no server store |
| cloud id (project ref) | 7/0 | 7/0 | 17673, 39054, 69436, 69456, 87657, 102502, 134517 (`net.http_post` to `…supabase.co/functions/v1/*`) | no server store (config.js:51 is client only) |

### workers

| file:lines | kind | n (code/cmt) | values | central? |
|---|---|---|---|---|
| workers/links/worker.js:2–379 | domain | 5/2 | digital.adspace.me×3, hi.adspace.me, go.adspace.me | no server store |
| workers/links/worker.js:270 | logo/wordmark | 1/0 | adspace-brandname | no server store |
| workers/links/worker.js:2–271 | name | 10/4 | ADspace×14 | no server store |
| workers/video-convert/index.mjs:17,122 | cloud id | 1/1 | ap-southeast-5, myadspace | no server store |

### manifest/PWA/site

| file:lines | kind | n (code/cmt) | values | central? |
|---|---|---|---|---|
| CNAME:1 | domain | 1/0 | digital.adspace.me | BYPASS |
| _config.yml:1 | domain | 0/1 | digital.adspace.me | comment only |
| admin/manifest.webmanifest:2,3,4 | name | 3/0 | ADspace×3 | BYPASS |
| creator/manifest.webmanifest:2,3 | name | 2/0 | ADspace×2 | BYPASS |
| creators/manifest.webmanifest:2,3 | name | 2/0 | ADspace×2 | BYPASS |
| robots.txt:1,7 | domain | 2/0 | digital.adspace.me×2 | BYPASS |
| sitemap.xml:4 | domain | 1/0 | digital.adspace.me | BYPASS |

### demo fixture

| file:lines | kind | n (code/cmt) | values | central? |
|---|---|---|---|---|
| demo/engine.js:17905,21837 | address | 4/0 | Mount Austin×2, Mutiara Emas, 81100 Johor | fixture |
| demo/engine.js:6067–22108 | domain | 18/0 | digital.adspace.me×10, hi.adspace.me×4, mycdn.adspace.me×3 | fixture |
| demo/engine.js:6067–19195 | legal name | 7/0 | ADSPACE PLT×7 | fixture |
| demo/engine.js:2021–16096 | mailbox | 12/0 | ap@adspacestudios.com×5, legal@adspacestudios.com×2, advertise@adspacestudios.com | fixture |
| demo/engine.js:740–21860 | name | 61/0 | ADspace×57, adspace×4 | fixture |
| demo/sample.json:33,34 | address | 2/0 | Mount Austin×2 | fixture |
| demo/seed.js:128,362 | address | 2/0 | 81100 Johor×2 | fixture |
| demo/seed.js:9 | name | 1/0 | ADspace | fixture |

### CI/other

| file:lines | kind | n (code/cmt) | values | central? |
|---|---|---|---|---|
| .claude-plugin/marketplace.json:4 | legal name | 1/0 | ADSPACE PLT | no server store |
| .claude-plugin/marketplace.json:6,11 | name | 2/0 | ADspace×2 | no server store |
| .github/stamp.js:30 | name | 1/0 | adspace | no server store |
| .github/workflows/db-backup.yml:35,36 | cloud id | 2/0 | myadspace, ap-southeast-5 | no server store |
| .github/workflows/pages.yml:1 | domain | 0/1 | digital.adspace.me | comment only |
### docs (md) — comment/doc text only, not served (Pages excludes notes)

| file | hits |
|---|---|
| docs/SIGN-IN-EMAILS.md | 52 |
| docs/S3-STORAGE.md | 33 |
| CLAUDE.md | 30 |
| docs/rules/print.md | 28 |
| docs/SUPPLIER-EMAIL-SETUP.md | 26 |
| docs/S3-UPLOAD-SETUP.md | 25 |
| docs/FIX-ACCESS-DENIED.md | 22 |
| docs/rules/hiring.md | 22 |
| docs/CONTENT-REVIEW-SETUP.md | 18 |
| docs/REPORTS-SOURCE-MAP.md | 17 |
| workers/links/README.md | 15 |
| docs/rules/documents.md | 14 |
| docs/rules/front-door.md | 14 |
| docs/rules/copy.md | 13 |
| docs/SIGN-IN-SECURITY.md | 12 |
| docs/rules/reports.md | 11 |
| docs/WHATSAPP-SETUP.md | 10 |
| docs/rules/short-links.md | 9 |
| DESIGN.md | 8 |
| docs/GOOGLE-MEET-SETUP.md | 8 |
| 34 further .md files | ≤6 each |

### C.4 Count table (area × kind, code/cmt)

| Area | name | legal name | registration | tax number | address | phone | domain | mailbox | mailbox placeholder | logo/wordmark | font | social/map URL | cloud id | Total (code / comment) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| portal pages | 96/10 | 3/0 |  |  | 7/0 |  | 37/2 | 8/0 | 8/0 | 3/0 | 18/1 | 6/0 |  | **186 / 13** |
| js | 258/44 | 20/4 | 1/0 | 1/0 | 4/0 | 1/2 | 19/21 | 3/0 | 7/0 | 2/0 | 4/8 | 13/0 | 1/0 | **334 / 79** |
| PDFs | 7/6 | 5/4 |  |  |  | 0/2 | 5/0 |  |  |  | 0/29 |  |  | **17 / 41** |
| css | 9/5 |  |  |  |  |  | 0/1 |  |  |  | 20/6 |  |  | **29 / 12** |
| emails & edge fns | 45/14 | 2/1 | 1/0 |  | 6/0 | 1/0 | 14/4 | 3/2 |  | 1/0 |  |  |  | **73 / 21** |
| schema & migrations | 222/129 | 19/57 | 4/0 |  | 12/0 | 2/0 | 74/49 | 43/8 | 0/1 |  |  | 10/8 | 14/0 | **400 / 252** |
| workers | 10/4 |  |  |  |  |  | 5/2 |  |  | 1/0 |  |  | 1/1 | **17 / 7** |
| manifest/PWA/site | 7/0 |  |  |  |  |  | 4/1 |  |  |  |  |  |  | **11 / 1** |
| demo fixture | 62/0 | 7/0 |  |  | 8/0 |  | 18/0 | 12/0 |  |  |  |  |  | **107 / 0** |
| CI/other | 3/0 | 1/0 |  |  |  |  | 0/1 |  |  |  |  |  | 2/0 | **6 / 1** |
| docs (md) | 0/150 | 0/19 | 0/3 | 0/1 | 0/8 | 0/4 | 0/118 | 0/29 | 0/4 | 0/9 | 0/65 | 0/2 | 0/63 | **0 / 475** |

**Visible hard-coded values: 2,082 matches (1,180 in code, 902 in comments/docs).** Internal identifiers, not visible (`ADspaceAdmin`, `ADSPACE_ORG`, `adspace-theme`, `adspace.sm` …): **5,410** (js 4,282). Non-agency placeholder mailboxes (`*@example.com`) excluded: 22. Agency-domain placeholders (`email@adspace.me` etc.) counted under "mailbox placeholder". Brand palette literals (`#515151`, `#a1a1a1`, `#cfd0d4`) outside tokens: 32 (PDF scripts 10, `css/console.css` 8, `css/portal.css` 5, `_shared/mail.ts` 7, `bukku-sync` 2) — documented document/email palette, not counted above.

### C.5 Guard patterns (PCRE / Python `re`; `rg -P`), counts on 2026-11-27, same scope

| kind | pattern | matches | files |
|---|---|---|---|
| name | `\b(?i:adspace)\b(?![.\-][A-Za-z0-9]\| PLT)` | 1081 | 214 |
| legal name | `ADSPACE PLT` | 142 | 66 |
| registration | `202304002162` | 9 | 7 |
| tax number | `J31-2401-32100002` | 2 | 2 |
| address | `(?i)Mutiara Emas\|Mount Austin\|81100 Johor` | 45 | 14 |
| phone | `762[ -]?5233\|60187625233` | 12 | 9 |
| domain | `(?i)(?<![@\w.-])(?:[a-z0-9-]+\.)*adspace\.me\b\|(?<![@\w.-])adspacestudios\.com\b` | 375 | 103 |
| mailbox | `(?i)[A-Za-z0-9._%+-]+@(?:[a-z0-9-]+\.)*(?:adspace\.me\|adspacestudios\.com)\b\|adspacestudios@gmail\.com` | 128 | 35 |
| logo | `(?i)adspace-brandname\|adspace-mark` | 16 | 9 |
| font | `(?i)\bslate(?:rg\|book\|medium)?\b\|\boptima\b` | 151 | 36 |
| social/map | `(?i)(?:facebook\|instagram\|linkedin\|tiktok)\.com/[\w./@]*adspace[\w.]*\|wa\.me/adspace\|google\.[a-z.]+/maps\|maps\.app\.goo\.gl` | 39 | 13 |
| cloud id | `\bmyadspace\b\|ap-southeast-5\|hwwuigvdfubuymchsvyx` | 82 | 22 |
| internal (not visible) | `\bADspace[A-Z][A-Za-z]*\|\bADSPACE_[A-Z]+\|\b(?i:adspace)[.\-](?!me\b\|brandname\|mark\b\|advertising)[a-z][\w-]*` | 5410 | 236 |

Pipes are escaped as `\|` for the table; use a bare `|` in the test. The scan was a one-off script, not committed; the guard test (F) re-implements these patterns.

## D. Content

Locations only; no wording copied. "Editable" = a person can change it in the console today. "Versioned" = a version number or effective-from kept. Line numbers as of 2026-11-27 HEAD.

### D.1 Agency IP — letters, quotations, terms

| # | Block | Location | Lang | Editable today? | Versioned? | Placeholders |
|---|---|---|---|---|---|---|
| 1 | Letter bodies: Quotation Cover, Thank You, Client letter, HR confirmation, HR letter (title, salutation, closing, body) | `doc_types` schema.sql:3716-3756 (seed); later rewrite :159548-159553 | EN, 中文, MS | yes: Documents (js/register.js:1603 `doc_type_save`), not Settings | no (issued letter keeps its copy) | yes (`{role}`, `{salary}`) |
| 2 | Letter of Offer body and TERMS (retired 2026-11-12; redraws issued letters) | js/documents.js:905-1230 (`drawDoc`; :1011, :1180-1194) | EN | no: code literal | no | no: string concatenation |
| 3 | Quotation Cover fallback (copy of #1 quote_cover) | js/quotepdf.js:47-53 `COVER` | EN | no | no | no |
| 4 | Quotation PDF terms: Advertising budget, Exclusions, Special terms, Agreement; ad-spend ways | js/quotepdf.js:61-76 `adWays`, :590-620 `grp(...)` | EN | no (figures from `app_settings` `ad_prepay_pct`, `ad_credit_fee_pct`; typed Special terms per quotation) | figures by issue date only | concatenation |
| 5 | Shared quotation lines (add-on lead/term, terms, WhatsApp-off notes) | js/words.js:436-540 | EN (+中文 where keyed) | no | no | some |
| 6 | Public quotation page: intro, steps, ad-spend prepay and credit-term explainer, refusals | js/quote.js:44-195 (EN), ~:200-400 (中文 table) | both | no | no | yes (`{pct}`, `{c}`, `{b}`, `{x}`) |
| 7 | Rate Card page text (What's included, notes, footnotes) | `rate_card_text` schema.sql:45276-45330 | EN | yes: Services (js/crm.js:8288 `rate_card_text_save`) | no (updated_at) | no |
| 8 | Service catalogue descriptions | `services` schema.sql:1901, seed rows ~:2429-2440 | EN | verify (Services catalogue) | Rate Card versions | no |
| 9 | Service Terms | off-repo URL js/config.js:130 `serviceTermsUrl` | n/a | outside portal | n/a | n/a |
| 10 | Word templates (letterhead, internal page, client letter signed/unsigned) | docs/templates/AL.dotx, ALP.dotx, ACL_SIGN.dotx, ACL_NOSIGN.dotx | EN | no (files) | no | no |
| 11 | /verify/ result notes (what a match confirms) | js/verify.js:28-40 | both | no | no | no |

### D.2 Agency IP — emails and WhatsApp

| # | Block | Location | Lang | Editable today? | Versioned? | Placeholders |
|---|---|---|---|---|---|---|
| 12 | Client email templates | `client_email_templates` schema.sql:90106 (seed :90116) | EN | yes: Settings › Messages (js/mailtpl.js) | no | yes |
| 13 | Supplier email templates | `supplier_email_templates` :63369 (seed :63379) | EN | yes: Settings › Messages | no | yes (`{currency}`…) |
| 14 | Creator email templates | `creator_email_templates` :102359 (seed :102370) | EN | yes: Settings › Messages | no | yes (`{payee}`, `{reference}`…) |
| 15 | Candidate (hiring) email templates | `hiring_email_templates` :136828 (seed :136839) | EN | yes: Settings › Messages | no | yes (`{position}`, `{times}`…) |
| 16 | Feedback request emails | `feedback_email_templates` :151154 (seed :151167) | both (`lang`) | yes: Settings › Messages | no | yes |
| 17 | Quotation request emails | `quote_email_templates` :162723 (seed :162736) | both (`lang`) | yes: Settings › Messages | no | yes |
| 18 | Invoice email / reminder | `invoice_email_template` :82679 (seed :82692; rewrite :83667) | EN | yes: Settings › Messages | no | yes |
| 19 | Invoice send | `invoice_send_template` :92754 (seed :92767) | EN | yes: Settings › Messages | no | yes |
| 20 | Sign-in code email | `code_email_template` :121008 (seed :121018) | EN | yes: Settings › Messages | no | yes |
| 21 | Free-form client/supplier emails | `email_templates` :93308 (seed :93390) | EN | yes: Settings › Messages | no | yes |
| 22 | Meeting message (Meet invite text) | `meeting_message_template` :83785 (seed :83794) | EN | yes: My Work (js/ops.js:7553 `meeting_message_save`) | no | yes |
| 23 | Email shell: sign-in code foot, layout lines | supabase/functions/_shared/mail.ts:28, :69, :125-126 | EN | no | no | concatenation |
| 24 | Colleague / client invitation email | supabase/functions/invite-member/index.ts:45-61 | EN | no | no | concatenation |
| 25 | Hiring mail fallbacks | supabase/functions/hiring-mail/index.ts:83-101 | EN | partly (DB templates #15 first) | no | yes |
| 26 | Supabase Auth emails (sign-in) | Supabase dashboard; names only js/mailtpl.js:52 | EN | dashboard | no | Supabase fills |
| 27 | WhatsApp templates | bodies held at Meta; `wa_templates` schema.sql:38929 (name, lang, params); purposes js/whatsapp.js:33-43 | per Meta template | name/lang: Settings › Messages › WhatsApp; body: Meta | Meta's | Meta `{{n}}` |

creator-mail, supplier-mail, quote-request, portal-login, push-send, wa-send: no long literals; they read #12-#22.

### D.3 Agency IP — HR, people, consent and privacy

| # | Block | Location | Lang | Editable today? | Versioned? | Placeholders |
|---|---|---|---|---|---|---|
| 28 | Employment offer and contract: title, declaration, clauses (duties, conflict, confidentiality, non-compete, termination…) | js/hrdocs.js:68-72, :77 `DECLARE`, :81-179 `clauses` | EN | no | no | record fields concatenated |
| 29 | Careers page: next steps, decision notes, talent-pool consent, offer acceptance | js/careers.js:35-38, :118-178, :281-297 | EN | no | no | concatenation |
| 30 | Talent-pool consent ask (console) | js/hiring.js:605-617 | EN | no | no | concatenation |
| 31 | Interview scorecard criteria | `hiring_scorecards` schema.sql:122391 (seed) | EN | yes: Hiring (js/hiring.js:1945) | no | no |
| 32 | Welcome kit (new colleague) | `welcome_kit` schema.sql:126616-126700 | EN | yes: Team onboarding (js/onboard.js:160 `welcome_kit_save`) | no (updated_at) | no |
| 33 | Personnel data consent declaration | js/personnel.js:573 | EN | no | no | no |
| 34 | Supplier declaration | js/supplierform.js:40-57, :127 | EN | no | no | no |
| 35 | Billing details form consent | js/details.js:25-36 | both | no | no | no |
| 36 | Creator payment and e-Invoice terms | js/creator.js:90-140 | both | no | no | no |
| 37 | Health agreement (care lines and terms) | `health_wordings` schema.sql:66896-66930; v2 :142536 | EN | no (read by `health_wording_now` only) | yes (`version`) | no |
| 38 | Health check-in explanations | js/health.js:183-198, :349; schema.sql:139474 | EN | no | no | no |
| 39 | Client feedback questions | `feedback_questions` schema.sql:147000 (`text_en`, `text_zh`) | both | no (read by `feedback_questions_of`) | no | no |

### D.4 Agency IP — method, guidance, criteria

| # | Block | Location | Lang | Editable today? | Versioned? | Placeholders |
|---|---|---|---|---|---|---|
| 40 | Ad report explainer (how ad spend, cost per result, hook rate read; WHT/SST note) | js/smreport.js:168-187 (中文 table), :1857-1905, :2184-2189, :2283-2284 | both | no | no | `{client}` |
| 41 | Handbook, SOPs, policies | `handbook_docs` / `handbook_versions` schema.sql:22626-22721 (files in Storage); js/handbook.js:357 | per file | yes: Handbook | yes (`version_no`) | n/a |
| 42 | First-visit guides | js/admin.js:2375-2512 `GUIDES` (engine js/guide.js) | EN | no | no | no |
| 43 | Performance review categories, paths, print explanations | js/perf.js:37-46 `CATS`, :171-174 `PATH`, :2136-2144 | EN | no (figures in `perf_settings`) | no | no |
| 44 | Client checklists (onboarding, pre-ads) | `checklist_template()` schema.sql:50212-50220, pre_ads :50659 | EN | no | yes (string `r1.1-26`, `r1.2-26`; copy kept per client) | no |
| 45 | Task templates | `ops_task_templates` schema.sql:4408 (seed :4839) | EN | yes: My Work / Settings (js/ops.js, js/settings.js) | no | no |
| 46 | Video script guidance lines | js/scripts.js:1131-1134 | EN | no | no | no |

### D.5 Agency IP — AI prompts (all code literals; none editable; none versioned; EN with 中文 switches)

| # | Function | Prompt constants (index.ts lines) |
|---|---|---|
| 47 | portal-agent | `SYSTEM` 65-89; `TOOLS` descriptions 112-187 |
| 48 | brand-analysis | `SYSTEM` 170-213; `SUBMIT` schema 254 |
| 49 | caption-draft | `SYSTEM` 44-69; `SAFE` 73-77 |
| 50 | checklist-draft | `SYSTEM` 74-124; `SUBMIT` 261 |
| 51 | report-draft | `AVOID` 103-109; `SHARED` 115-135; `ZH` 137-142; `ZH_ASK` 147; `SYSTEM` 160-190; `SOCIAL_SYSTEM` 196-217; `CHECK` 222-238; `NEXT` 247-267 |
| 52 | script-draft | `SYSTEM` 78-142; `SAFE` 146-150; `REVIEW` 153-170 |
| 53 | script-pictures | `SYSTEM` 56-70 |
| 54 | analytics-read | `SYSTEM` 55-79; `SCHEMA` 81 |

meta-import calls no model. No prompt is stored in the database or `app_settings`.

### D.6 Neutral UI (labels, buttons, refusals, empty states)

95 of 96 js files hold person-facing literals (config.js aside from a few). Literals / phrases (with a space) / 中文, by file, largest first:

reports 2841/1717/6 · admin 3095/1698/6 · ops 2920/1548/1 · campaigns 2749/1530/1 · perf 2024/1032/0 · quotes 1818/944/0 · quote 1900/822/379 · team 1403/796/0 · hiring 1237/734/0 · personnel 1104/706/0 · overview 1052/654/0 · settings 1045/653/3 · scripts 1046/479/45 · agent 753/395/1 · suppliers 779/383/0 · creator 926/376/187 · whatsapp 832/365/0 · outstation 551/319/0 · analytics 441/304/0 · portal 1029/299/212 · register 956/296/0 · smreport 639/260/180 · health 501/253/0 · checklists 419/232/0 · words 446/227/156 · creators 680/225/128 · careers 324/205/0 · bukku 303/201/0 · icons 270/189/1 · onboard 326/175/0 · supplierform 315/173/0 · invoices 324/173/0 · quotepdf 214/159/0 · hrdocs 232/149/0 · review 282/137/2 · documents 252/136/8 · mailtpl 210/131/2 · handbook 277/129/0 · verify 299/114/74 · mockups 127/101/2 · chart 170/101/0 · details 242/88/43 · seal 139/87/0 · script 174/84/0 · payments 137/81/0 · frames 82/81/0 · ratecardpdf 119/79/0 · notice 140/78/0 · delreq 102/69/0 · announce 154/65/5 · letters 89/64/0 · engage 115/62/0 · form 186/59/0 · search 168/53/0 · namecard 132/48/0 · passkey 84/47/0 · docmail 110/46/0 · cmdbar 88/45/0 · chrome 80/40/4 · confirm 74/39/0 · money 87/37/6 · maintenance 73/37/0 · records 58/36/0 · demo 67/34/0 · feedback 73/30/14 · fbform 56/29/6 · api 64/28/0 · sheet 43/25/0 · hrforms 29/22/0 · state 36/20/0 · scriptpdf 41/20/0 · 24 smaller files under 20 phrases each. crm.js (9,119 lines) under-counted by the rough scanner (181/146): treat as large.
Refusal maps (`SAID`, `WORD`, `ISSUE_WORD`, `AGAIN_SAID`) are neutral UI, in nearly every section script.
Edge functions: 84 literals of 12+ words across `supabase/functions/`, mostly prompts (D.5) and refusals.

### D.7 Counts

| Measure | Count |
|---|---|
| Agency-IP blocks | **54** |
| Letters, quotations, terms (D.1) | 11 |
| Emails and WhatsApp (D.2) | 16 |
| HR, consent, privacy (D.3) | 12 |
| Method, guidance, criteria (D.4) | 7 |
| AI prompt sets (D.5) | 8 functions, 23 constants |
| Editable in the console today | 19 (#1, 7, 12-22, 31, 32, 41, 45; #25, #27 partly) |
| Editable in Settings itself | 11 (Settings › Messages: #12-21, #27 names) |
| Bilingual (EN and 中文) | 11 (#1, 6, 11, 16, 17, 35, 36, 39, 40; #5 partly; AI prompts switch to 中文 in report-draft) |
| Versioned | 4 (#37 health, #41 handbook, #44 checklists, #4 figures by date) |
| With placeholders | 19 |
| Neutral-UI files | 95 js + 20 edge functions |

### D.8 Contentguard patterns (today's count)

| Pattern | Count today |
|---|---|
| String literal of 12+ words in `js/*.js`, excluding words.js, mailtpl.js, crm.js | 921 in 51 files |
| … of 20+ words | 149 in 28 files |
| … of 30+ words | 55 in 11 files |
| `para('` literal of 40+ characters (PDF body typed in code) | 51 in documents.js, hrdocs.js, perf.js, quotepdf.js |
| Contract register (`shall`) inside a js literal | 18 in hrdocs.js, quotepdf.js, supplierform.js |
| Top-level template-literal constant in an edge function (`const X = \``) | 17 (all prompts) |
| Literal of 12+ words in `supabase/functions/**` | 84 |
| Schema `E'…'` line of 150+ characters (seeded wording) | 55 |
