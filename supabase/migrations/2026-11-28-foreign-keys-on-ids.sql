-- ===========================================================================
-- FOREIGN KEYS ON SINGLE-TARGET IDS (2026-11-28)
-- ===========================================================================
-- WHY: the restructure's release 4 (docs/MAP.md §G, risk 4; the user, 28 Nov:
-- "go for release 4 too"). 89 uuid columns held no foreign key, so a delete
-- left rows pointing at nothing; 47 keys stated no `on delete`. Each key now
-- says what a delete of its parent does, from the record's meaning: cascade
-- only where the child cannot stand without its parent, set null where the
-- history must survive (a soft remove comes before a hard delete; a
-- contact's keys are set null), restrict where the delete should be refused.
--
-- WHAT IT CHANGES
--   * 62 new keys, each added `not valid` and then validated where no live
--     row points at nothing. One holds orphans and stays `not valid` until
--     the user decides (new rows are still checked): `wa_outbox.client_id`,
--     2 rows of 29 Oct 2026 naming a client since deleted.
--   * 37 keys that stated no `on delete` restated with one. A restrict
--     behaves as before; a set null or cascade on `team_members` does what
--     `team_member_purge` already did by hand (it clears only keys with no
--     action or restrict).
--   One line a key, `table.column -> parent: on delete … · why`:
--     bukku_links_gone.sent_by -> team_members: set null · who sent a Bukku unlink; the record of it stays
--     bukku_send_claims.claimed_by -> team_members: set null · a send claim outlives the colleague who held it
--     campaigns.invoice_claimed_by -> team_members: set null · the campaign stays; only who claimed its invoice clears
--     code_email_template.updated_by -> team_members: set null · a template stays; who last edited it clears
--     creator_email_templates.updated_by -> team_members: set null · as above
--     creator_emails.sent_by -> team_members: set null · the record of an email sent stays
--     creator_pay_requests.decided_by -> team_members: set null · a payment request's decision stays
--     creator_sheet_settings.updated_by -> team_members: set null · a setting stays; who edited it clears
--     departments.updated_by -> team_members: set null · as above
--     email_templates.updated_by -> team_members: set null · as above
--     hiring_email_templates.updated_by -> team_members: set null · as above
--     id_formats.updated_by -> team_members: set null · as above
--     ops_tasks.delayed_by -> team_members: set null · a task stays; who moved its date clears
--     outstation_photos.removed_by -> team_members: set null · a removed photo stays removed; who removed it clears
--     perf_events.actor_id -> team_members: set null · a performance event is history
--     personnel_records.requested_by -> team_members: set null · a colleague's record stays
--     personnel_records.superior_id -> team_members: set null · a record outlives its superior
--     personnel_records.updated_by -> team_members: set null · as above
--     personnel_salaries.updated_by -> team_members: set null · a salary row stays
--     personnel_settings.updated_by -> team_members: set null · a setting stays
--     sm_report_post_links.linked_by -> team_members: set null · a link stays; who made it clears
--     sm_report_post_links.unlinked_by -> team_members: set null · as above
--     system_emails.sent_by -> team_members: set null · the record of an email sent stays
--     team_emails.sent_by -> team_members: set null · as above
--     team_invites.caller_id -> team_members: cascade · the colleague's own invitation count, read only against their next invitation
--     team_notices.sent_by -> team_members: set null · a notice stays (its sender's name is kept as written)
--     video_scripts.created_by -> team_members: set null · a script stays (its author's name is kept as written)
--     ai_drafts.client_id -> clients: set null · an AI use is counted against the month's limit after its client goes
--     client_brands.client_id -> clients: cascade · a brand is the client's and cannot stand alone
--     client_document_deletions.client_id -> clients: set null · the record of a deleted document stays
--     delete_requests.client_id -> clients: set null · a delete request is history once decided
--     ops_month_invoices.client_id -> clients: cascade · a month's invoice check is the client's own (its month already cascades)
--     sm_reports.label_client -> clients: set null · a report keeps its own client; the white label clears (a published report's guard refuses it)
--     system_emails.client_id -> clients: set null · the record of an email sent stays
--     team_emails.client_id -> clients: set null · as above (DECISIONS: removing a client never removes what was sent to it)
--     wa_outbox.client_id -> clients: set null · a WhatsApp message sent stays
--     creator_emails.again_of -> creator_emails: set null · a resend stands alone once its first is gone
--     creator_pay_requests.prior_id -> creator_pay_requests: set null · a later request stands alone
--     hiring_docs.replaces -> hiring_docs: set null · a replacement stands alone
--     system_emails.again_of -> system_emails: set null · a resend stands alone
--     ai_drafts.script_id -> video_scripts: set null · an AI use stays counted
--     ops_notifications.script_id -> video_scripts: cascade · a notification about a script goes with it, as one about a task does
--     supplier_emails.document_id -> documents: set null · the record of an email sent stays
--     ops_recurring_made.source_task_id -> ops_tasks: set null · the date made stays, so a repeat does not make it again
--     sm_report_post_links.task_id -> ops_tasks: cascade · a post's link to a task cannot stand without the task
--     ops_tasks.delayed_report -> sm_reports: set null · a task stays; the report that delayed it clears
--     sm_report_post_links.report_id -> sm_reports: cascade · a link cannot stand without its report
--     ai_drafts.batch_id -> batches: set null · an AI use stays counted
--     billing_entities.orphan_of -> billing_entities: set null · an entity stands alone once the one it split from goes
--     brand_analyses.press_id -> ai_drafts: set null · an analysis stays; its use record clears
--     client_entities.bill_contact_id -> client_contacts: set null · a contact's keys are set null (DESIGN §7); the main contact is then billed
--     creator_emails.creator_id -> creators: set null · the record of an email sent stays
--     creator_emails.request_id -> creator_pay_requests: set null · as above
--     creator_emails.option_id -> campaign_options: set null · as above
--     ops_notifications.notice_id -> team_notices: cascade · a notice's notifications go with it (notice delete already removes them)
--     ops_revisions.source_review_id -> reviews: set null · a revision stays; the review that asked for it clears
--     quotation_link_copies.quotation_id -> quotations: cascade · a copy's visit log is the quotation's own
--     quotations.version_id -> rate_card_versions: restrict · a rate card a quotation was priced from is never deleted under it
--     sm_report_post_links.post_id -> sm_report_posts: cascade · a link cannot stand without its post
--     system_emails.candidate_id -> hiring_candidates: set null · the record of an email sent stays
--     team_emails.supplier_id -> suppliers: set null · as above
--     team_emails.template_id -> email_templates: set null · as above
--   Restated:
--     delete_requests.kind -> delete_kinds: restrict · a kind in use is never deleted
--     perf_dept_scores.department -> departments: restrict · department_delete already refuses one in use
--     perf_people.department -> departments: restrict · as above
--     mail_senders.box -> mail_boxes: restrict · a mailbox a sender replies to is never deleted
--     ops_recurring_rules.template_id -> ops_task_templates: restrict · ops_template_delete already refuses one in use
--     ops_tasks.template_id -> ops_task_templates: restrict · as above
--     ops_task_templates.workflow_id -> ops_workflows: restrict · a workflow in use is never deleted
--     ops_tasks.workflow_id -> ops_workflows: restrict · as above
--     client_services.quotation_id -> quotations: restrict · a quotation that made a service line is kept (as before)
--     clients.vic_by -> team_members: set null · the client stays; who marked it clears
--     creator_pay_requests.entered_by -> team_members: set null · the request stays
--     delete_requests.decided_by -> team_members: set null · the decision stays
--     delete_requests.requested_by -> team_members: cascade · the colleague's own requests (team_member_purge already deleted them)
--     guide_seen.team_member_id -> team_members: cascade · the colleague's own guide marks
--     invoice_send_template.updated_by -> team_members: set null · a template stays
--     ops_due_requests.asked_by -> team_members: cascade · the colleague's own date requests (purge already deleted them)
--     ops_due_requests.decided_by -> team_members: set null · the decision stays
--     ops_due_requests.decider_id -> team_members: set null · as above
--     ops_engagement_checks.updated_by -> team_members: set null · a month's check stays
--     ops_engagement_events.actor_id -> team_members: set null · a month's history stays
--     ops_engagements.created_by -> team_members: set null · a month stays
--     ops_engagements.manager_id -> team_members: set null · a month outlives its manager
--     ops_recurring_rules.created_by -> team_members: set null · a repeat stays
--     ops_revisions.requested_by -> team_members: set null · a revision stays
--     ops_task_checklist_items.completed_by -> team_members: set null · a ticked item stays ticked
--     ops_task_events.actor_id -> team_members: set null · a task's history stays
--     ops_task_links.created_by -> team_members: set null · a link stays
--     ops_tasks.created_by -> team_members: set null · a task stays
--     ops_tasks.manager_id -> team_members: set null · a task outlives its manager
--     ops_tasks.rated_by -> team_members: set null · a rating stays
--     ops_work_sessions.corrected_by -> team_members: set null · a session stays
--     ops_work_sessions.team_member_id -> team_members: cascade · the colleague's own time (purge already deleted it)
--     option_reviews.undone_by -> team_members: set null · a review stays
--     outstation_trips.driver_id -> team_members: cascade · the colleague's own trips (purge refuses first where another colleague joined)
--     personnel_records.team_member_id -> team_members: cascade · a personnel record is the colleague's own (purge already deleted it)
--     personnel_salaries.team_member_id -> team_members: cascade · as above
--     rail_orders.member_id -> team_members: cascade · the colleague's own rail order
--
-- LEFT ALONE
--   * The 16 polymorphic columns (MAP-INVENTORY A.2.3: bukku_links,
--     bukku_links_gone and bukku_send_claims.record_id, activity_log.ref,
--     ops_tasks.source_id, ops_task_links.ref_id, wa_outbox.ref_id and
--     to_id, system_emails.ref_id, client_emails.ref_id,
--     signing_steps.doc_id, verify_checks.doc_id, verify_check_totals.doc_id,
--     agent_schedules.condition_ref, push_subscriptions.target,
--     push_outbox.target): no single parent, so no key is possible.
--   * uuid arrays, which a key cannot hold: client_document_deletions
--     .service_ids, outstation_trips.companions, team_notices.recipients.
--   * Not links: video_scripts.series_id (a series' own group id) and
--     posts.cover_for (no key by design).
--   * Recorded decisions that the id outlives its parent unchanged:
--     perf_breaches.client_id ("removing a client never touches a
--     review"), campaign_confirmations.client_id and campaign_id (rows
--     outlive the campaign) and client_document_deletions.document_id (the
--     record of a document already deleted).
--   * Columns other releases change today: ai_drafts.brand_id and
--     sm_reports.brand_id (lookups by id), industries.updated_by
--     (industries rekeyed), and the owner, assigned, sales-by and
--     team_members keys among the 47 (clients.sales_by,
--     ops_engagement_checks.owner_id, ops_engagements.meeting_owner_id,
--     ops_recurring_rules.owner_id, ops_task_templates.default_owner_id,
--     ops_revisions.assigned_to, ops_task_assignees.team_member_id and
--     assigned_by, team_members.department and role).
--
-- ORDER: this file alone; no page or function changes. An open tab meets
-- the same answers; a delete of a parent now clears or removes what its
-- key says instead of failing or leaving an orphan.
-- Safe to run twice: each key is dropped and added again `not valid`, then
-- validated where its rows allow. Holds no delete of data.
-- ROLLBACK: drop each key this file adds (`alter table public.{table} drop
-- constraint if exists {table}_{column}_fkey`), and for the 37 restated
-- run their earlier bands' definitions again (`foreign key ({column})
-- references public.{parent}(…)` with no `on delete`).
-- ===========================================================================

-- FOREIGN KEYS ON SINGLE-TARGET IDS ----------------------------------------

alter table public.bukku_links_gone drop constraint if exists bukku_links_gone_sent_by_fkey;
alter table public.bukku_links_gone add constraint bukku_links_gone_sent_by_fkey
  foreign key (sent_by) references public.team_members(id) on delete set null not valid;
alter table public.bukku_send_claims drop constraint if exists bukku_send_claims_claimed_by_fkey;
alter table public.bukku_send_claims add constraint bukku_send_claims_claimed_by_fkey
  foreign key (claimed_by) references public.team_members(id) on delete set null not valid;
alter table public.campaigns drop constraint if exists campaigns_invoice_claimed_by_fkey;
alter table public.campaigns add constraint campaigns_invoice_claimed_by_fkey
  foreign key (invoice_claimed_by) references public.team_members(id) on delete set null not valid;
alter table public.code_email_template drop constraint if exists code_email_template_updated_by_fkey;
alter table public.code_email_template add constraint code_email_template_updated_by_fkey
  foreign key (updated_by) references public.team_members(id) on delete set null not valid;
alter table public.creator_email_templates drop constraint if exists creator_email_templates_updated_by_fkey;
alter table public.creator_email_templates add constraint creator_email_templates_updated_by_fkey
  foreign key (updated_by) references public.team_members(id) on delete set null not valid;
alter table public.creator_emails drop constraint if exists creator_emails_sent_by_fkey;
alter table public.creator_emails add constraint creator_emails_sent_by_fkey
  foreign key (sent_by) references public.team_members(id) on delete set null not valid;
alter table public.creator_pay_requests drop constraint if exists creator_pay_requests_decided_by_fkey;
alter table public.creator_pay_requests add constraint creator_pay_requests_decided_by_fkey
  foreign key (decided_by) references public.team_members(id) on delete set null not valid;
alter table public.creator_sheet_settings drop constraint if exists creator_sheet_settings_updated_by_fkey;
alter table public.creator_sheet_settings add constraint creator_sheet_settings_updated_by_fkey
  foreign key (updated_by) references public.team_members(id) on delete set null not valid;
alter table public.departments drop constraint if exists departments_updated_by_fkey;
alter table public.departments add constraint departments_updated_by_fkey
  foreign key (updated_by) references public.team_members(id) on delete set null not valid;
alter table public.email_templates drop constraint if exists email_templates_updated_by_fkey;
alter table public.email_templates add constraint email_templates_updated_by_fkey
  foreign key (updated_by) references public.team_members(id) on delete set null not valid;
alter table public.hiring_email_templates drop constraint if exists hiring_email_templates_updated_by_fkey;
alter table public.hiring_email_templates add constraint hiring_email_templates_updated_by_fkey
  foreign key (updated_by) references public.team_members(id) on delete set null not valid;
alter table public.id_formats drop constraint if exists id_formats_updated_by_fkey;
alter table public.id_formats add constraint id_formats_updated_by_fkey
  foreign key (updated_by) references public.team_members(id) on delete set null not valid;
alter table public.ops_tasks drop constraint if exists ops_tasks_delayed_by_fkey;
alter table public.ops_tasks add constraint ops_tasks_delayed_by_fkey
  foreign key (delayed_by) references public.team_members(id) on delete set null not valid;
alter table public.outstation_photos drop constraint if exists outstation_photos_removed_by_fkey;
alter table public.outstation_photos add constraint outstation_photos_removed_by_fkey
  foreign key (removed_by) references public.team_members(id) on delete set null not valid;
alter table public.perf_events drop constraint if exists perf_events_actor_id_fkey;
alter table public.perf_events add constraint perf_events_actor_id_fkey
  foreign key (actor_id) references public.team_members(id) on delete set null not valid;
alter table public.personnel_records drop constraint if exists personnel_records_requested_by_fkey;
alter table public.personnel_records add constraint personnel_records_requested_by_fkey
  foreign key (requested_by) references public.team_members(id) on delete set null not valid;
alter table public.personnel_records drop constraint if exists personnel_records_superior_id_fkey;
alter table public.personnel_records add constraint personnel_records_superior_id_fkey
  foreign key (superior_id) references public.team_members(id) on delete set null not valid;
alter table public.personnel_records drop constraint if exists personnel_records_updated_by_fkey;
alter table public.personnel_records add constraint personnel_records_updated_by_fkey
  foreign key (updated_by) references public.team_members(id) on delete set null not valid;
alter table public.personnel_salaries drop constraint if exists personnel_salaries_updated_by_fkey;
alter table public.personnel_salaries add constraint personnel_salaries_updated_by_fkey
  foreign key (updated_by) references public.team_members(id) on delete set null not valid;
alter table public.personnel_settings drop constraint if exists personnel_settings_updated_by_fkey;
alter table public.personnel_settings add constraint personnel_settings_updated_by_fkey
  foreign key (updated_by) references public.team_members(id) on delete set null not valid;
alter table public.sm_report_post_links drop constraint if exists sm_report_post_links_linked_by_fkey;
alter table public.sm_report_post_links add constraint sm_report_post_links_linked_by_fkey
  foreign key (linked_by) references public.team_members(id) on delete set null not valid;
alter table public.sm_report_post_links drop constraint if exists sm_report_post_links_unlinked_by_fkey;
alter table public.sm_report_post_links add constraint sm_report_post_links_unlinked_by_fkey
  foreign key (unlinked_by) references public.team_members(id) on delete set null not valid;
alter table public.system_emails drop constraint if exists system_emails_sent_by_fkey;
alter table public.system_emails add constraint system_emails_sent_by_fkey
  foreign key (sent_by) references public.team_members(id) on delete set null not valid;
alter table public.team_emails drop constraint if exists team_emails_sent_by_fkey;
alter table public.team_emails add constraint team_emails_sent_by_fkey
  foreign key (sent_by) references public.team_members(id) on delete set null not valid;
alter table public.team_invites drop constraint if exists team_invites_caller_id_fkey;
alter table public.team_invites add constraint team_invites_caller_id_fkey
  foreign key (caller_id) references public.team_members(id) on delete cascade not valid;
alter table public.team_notices drop constraint if exists team_notices_sent_by_fkey;
alter table public.team_notices add constraint team_notices_sent_by_fkey
  foreign key (sent_by) references public.team_members(id) on delete set null not valid;
alter table public.video_scripts drop constraint if exists video_scripts_created_by_fkey;
alter table public.video_scripts add constraint video_scripts_created_by_fkey
  foreign key (created_by) references public.team_members(id) on delete set null not valid;
alter table public.ai_drafts drop constraint if exists ai_drafts_client_id_fkey;
alter table public.ai_drafts add constraint ai_drafts_client_id_fkey
  foreign key (client_id) references public.clients(id) on delete set null not valid;
alter table public.client_brands drop constraint if exists client_brands_client_id_fkey;
alter table public.client_brands add constraint client_brands_client_id_fkey
  foreign key (client_id) references public.clients(id) on delete cascade not valid;
alter table public.client_document_deletions drop constraint if exists client_document_deletions_client_id_fkey;
alter table public.client_document_deletions add constraint client_document_deletions_client_id_fkey
  foreign key (client_id) references public.clients(id) on delete set null not valid;
alter table public.delete_requests drop constraint if exists delete_requests_client_id_fkey;
alter table public.delete_requests add constraint delete_requests_client_id_fkey
  foreign key (client_id) references public.clients(id) on delete set null not valid;
alter table public.ops_month_invoices drop constraint if exists ops_month_invoices_client_id_fkey;
alter table public.ops_month_invoices add constraint ops_month_invoices_client_id_fkey
  foreign key (client_id) references public.clients(id) on delete cascade not valid;
alter table public.sm_reports drop constraint if exists sm_reports_label_client_fkey;
alter table public.sm_reports add constraint sm_reports_label_client_fkey
  foreign key (label_client) references public.clients(id) on delete set null not valid;
alter table public.system_emails drop constraint if exists system_emails_client_id_fkey;
alter table public.system_emails add constraint system_emails_client_id_fkey
  foreign key (client_id) references public.clients(id) on delete set null not valid;
alter table public.team_emails drop constraint if exists team_emails_client_id_fkey;
alter table public.team_emails add constraint team_emails_client_id_fkey
  foreign key (client_id) references public.clients(id) on delete set null not valid;
alter table public.wa_outbox drop constraint if exists wa_outbox_client_id_fkey;
alter table public.wa_outbox add constraint wa_outbox_client_id_fkey
  foreign key (client_id) references public.clients(id) on delete set null not valid;
alter table public.creator_emails drop constraint if exists creator_emails_again_of_fkey;
alter table public.creator_emails add constraint creator_emails_again_of_fkey
  foreign key (again_of) references public.creator_emails(id) on delete set null not valid;
alter table public.creator_pay_requests drop constraint if exists creator_pay_requests_prior_id_fkey;
alter table public.creator_pay_requests add constraint creator_pay_requests_prior_id_fkey
  foreign key (prior_id) references public.creator_pay_requests(id) on delete set null not valid;
alter table public.hiring_docs drop constraint if exists hiring_docs_replaces_fkey;
alter table public.hiring_docs add constraint hiring_docs_replaces_fkey
  foreign key (replaces) references public.hiring_docs(id) on delete set null not valid;
alter table public.system_emails drop constraint if exists system_emails_again_of_fkey;
alter table public.system_emails add constraint system_emails_again_of_fkey
  foreign key (again_of) references public.system_emails(id) on delete set null not valid;
alter table public.ai_drafts drop constraint if exists ai_drafts_script_id_fkey;
alter table public.ai_drafts add constraint ai_drafts_script_id_fkey
  foreign key (script_id) references public.video_scripts(id) on delete set null not valid;
alter table public.ops_notifications drop constraint if exists ops_notifications_script_id_fkey;
alter table public.ops_notifications add constraint ops_notifications_script_id_fkey
  foreign key (script_id) references public.video_scripts(id) on delete cascade not valid;
alter table public.supplier_emails drop constraint if exists supplier_emails_document_id_fkey;
alter table public.supplier_emails add constraint supplier_emails_document_id_fkey
  foreign key (document_id) references public.documents(id) on delete set null not valid;
alter table public.ops_recurring_made drop constraint if exists ops_recurring_made_source_task_id_fkey;
alter table public.ops_recurring_made add constraint ops_recurring_made_source_task_id_fkey
  foreign key (source_task_id) references public.ops_tasks(id) on delete set null not valid;
alter table public.sm_report_post_links drop constraint if exists sm_report_post_links_task_id_fkey;
alter table public.sm_report_post_links add constraint sm_report_post_links_task_id_fkey
  foreign key (task_id) references public.ops_tasks(id) on delete cascade not valid;
alter table public.ops_tasks drop constraint if exists ops_tasks_delayed_report_fkey;
alter table public.ops_tasks add constraint ops_tasks_delayed_report_fkey
  foreign key (delayed_report) references public.sm_reports(id) on delete set null not valid;
alter table public.sm_report_post_links drop constraint if exists sm_report_post_links_report_id_fkey;
alter table public.sm_report_post_links add constraint sm_report_post_links_report_id_fkey
  foreign key (report_id) references public.sm_reports(id) on delete cascade not valid;
alter table public.ai_drafts drop constraint if exists ai_drafts_batch_id_fkey;
alter table public.ai_drafts add constraint ai_drafts_batch_id_fkey
  foreign key (batch_id) references public.batches(id) on delete set null not valid;
alter table public.billing_entities drop constraint if exists billing_entities_orphan_of_fkey;
alter table public.billing_entities add constraint billing_entities_orphan_of_fkey
  foreign key (orphan_of) references public.billing_entities(id) on delete set null not valid;
alter table public.brand_analyses drop constraint if exists brand_analyses_press_id_fkey;
alter table public.brand_analyses add constraint brand_analyses_press_id_fkey
  foreign key (press_id) references public.ai_drafts(id) on delete set null not valid;
alter table public.client_entities drop constraint if exists client_entities_bill_contact_id_fkey;
alter table public.client_entities add constraint client_entities_bill_contact_id_fkey
  foreign key (bill_contact_id) references public.client_contacts(id) on delete set null not valid;
alter table public.creator_emails drop constraint if exists creator_emails_creator_id_fkey;
alter table public.creator_emails add constraint creator_emails_creator_id_fkey
  foreign key (creator_id) references public.creators(id) on delete set null not valid;
alter table public.creator_emails drop constraint if exists creator_emails_request_id_fkey;
alter table public.creator_emails add constraint creator_emails_request_id_fkey
  foreign key (request_id) references public.creator_pay_requests(id) on delete set null not valid;
alter table public.creator_emails drop constraint if exists creator_emails_option_id_fkey;
alter table public.creator_emails add constraint creator_emails_option_id_fkey
  foreign key (option_id) references public.campaign_options(id) on delete set null not valid;
alter table public.ops_notifications drop constraint if exists ops_notifications_notice_id_fkey;
alter table public.ops_notifications add constraint ops_notifications_notice_id_fkey
  foreign key (notice_id) references public.team_notices(id) on delete cascade not valid;
alter table public.ops_revisions drop constraint if exists ops_revisions_source_review_id_fkey;
alter table public.ops_revisions add constraint ops_revisions_source_review_id_fkey
  foreign key (source_review_id) references public.reviews(id) on delete set null not valid;
alter table public.quotation_link_copies drop constraint if exists quotation_link_copies_quotation_id_fkey;
alter table public.quotation_link_copies add constraint quotation_link_copies_quotation_id_fkey
  foreign key (quotation_id) references public.quotations(id) on delete cascade not valid;
alter table public.quotations drop constraint if exists quotations_version_id_fkey;
alter table public.quotations add constraint quotations_version_id_fkey
  foreign key (version_id) references public.rate_card_versions(id) on delete restrict not valid;
alter table public.sm_report_post_links drop constraint if exists sm_report_post_links_post_id_fkey;
alter table public.sm_report_post_links add constraint sm_report_post_links_post_id_fkey
  foreign key (post_id) references public.sm_report_posts(id) on delete cascade not valid;
alter table public.system_emails drop constraint if exists system_emails_candidate_id_fkey;
alter table public.system_emails add constraint system_emails_candidate_id_fkey
  foreign key (candidate_id) references public.hiring_candidates(id) on delete set null not valid;
alter table public.team_emails drop constraint if exists team_emails_supplier_id_fkey;
alter table public.team_emails add constraint team_emails_supplier_id_fkey
  foreign key (supplier_id) references public.suppliers(id) on delete set null not valid;
alter table public.team_emails drop constraint if exists team_emails_template_id_fkey;
alter table public.team_emails add constraint team_emails_template_id_fkey
  foreign key (template_id) references public.email_templates(id) on delete set null not valid;
alter table public.delete_requests drop constraint if exists delete_requests_kind_fkey;
alter table public.delete_requests add constraint delete_requests_kind_fkey
  foreign key (kind) references public.delete_kinds(kind) on delete restrict not valid;
alter table public.perf_dept_scores drop constraint if exists perf_dept_scores_department_fkey;
alter table public.perf_dept_scores add constraint perf_dept_scores_department_fkey
  foreign key (department) references public.departments(key) on delete restrict not valid;
alter table public.perf_people drop constraint if exists perf_people_department_fkey;
alter table public.perf_people add constraint perf_people_department_fkey
  foreign key (department) references public.departments(key) on delete restrict not valid;
alter table public.mail_senders drop constraint if exists mail_senders_box_fkey;
alter table public.mail_senders add constraint mail_senders_box_fkey
  foreign key (box) references public.mail_boxes(key) on delete restrict not valid;
alter table public.ops_recurring_rules drop constraint if exists ops_recurring_rules_template_id_fkey;
alter table public.ops_recurring_rules add constraint ops_recurring_rules_template_id_fkey
  foreign key (template_id) references public.ops_task_templates(id) on delete restrict not valid;
alter table public.ops_tasks drop constraint if exists ops_tasks_template_id_fkey;
alter table public.ops_tasks add constraint ops_tasks_template_id_fkey
  foreign key (template_id) references public.ops_task_templates(id) on delete restrict not valid;
alter table public.ops_task_templates drop constraint if exists ops_task_templates_workflow_id_fkey;
alter table public.ops_task_templates add constraint ops_task_templates_workflow_id_fkey
  foreign key (workflow_id) references public.ops_workflows(id) on delete restrict not valid;
alter table public.ops_tasks drop constraint if exists ops_tasks_workflow_id_fkey;
alter table public.ops_tasks add constraint ops_tasks_workflow_id_fkey
  foreign key (workflow_id) references public.ops_workflows(id) on delete restrict not valid;
alter table public.client_services drop constraint if exists client_services_quotation_id_fkey;
alter table public.client_services add constraint client_services_quotation_id_fkey
  foreign key (quotation_id) references public.quotations(id) on delete restrict not valid;
alter table public.clients drop constraint if exists clients_vic_by_fkey;
alter table public.clients add constraint clients_vic_by_fkey
  foreign key (vic_by) references public.team_members(id) on delete set null not valid;
alter table public.creator_pay_requests drop constraint if exists creator_pay_requests_entered_by_fkey;
alter table public.creator_pay_requests add constraint creator_pay_requests_entered_by_fkey
  foreign key (entered_by) references public.team_members(id) on delete set null not valid;
alter table public.delete_requests drop constraint if exists delete_requests_decided_by_fkey;
alter table public.delete_requests add constraint delete_requests_decided_by_fkey
  foreign key (decided_by) references public.team_members(id) on delete set null not valid;
alter table public.delete_requests drop constraint if exists delete_requests_requested_by_fkey;
alter table public.delete_requests add constraint delete_requests_requested_by_fkey
  foreign key (requested_by) references public.team_members(id) on delete cascade not valid;
alter table public.guide_seen drop constraint if exists guide_seen_team_member_id_fkey;
alter table public.guide_seen add constraint guide_seen_team_member_id_fkey
  foreign key (team_member_id) references public.team_members(id) on delete cascade not valid;
alter table public.invoice_send_template drop constraint if exists invoice_send_template_updated_by_fkey;
alter table public.invoice_send_template add constraint invoice_send_template_updated_by_fkey
  foreign key (updated_by) references public.team_members(id) on delete set null not valid;
alter table public.ops_due_requests drop constraint if exists ops_due_requests_asked_by_fkey;
alter table public.ops_due_requests add constraint ops_due_requests_asked_by_fkey
  foreign key (asked_by) references public.team_members(id) on delete cascade not valid;
alter table public.ops_due_requests drop constraint if exists ops_due_requests_decided_by_fkey;
alter table public.ops_due_requests add constraint ops_due_requests_decided_by_fkey
  foreign key (decided_by) references public.team_members(id) on delete set null not valid;
alter table public.ops_due_requests drop constraint if exists ops_due_requests_decider_id_fkey;
alter table public.ops_due_requests add constraint ops_due_requests_decider_id_fkey
  foreign key (decider_id) references public.team_members(id) on delete set null not valid;
alter table public.ops_engagement_checks drop constraint if exists ops_engagement_checks_updated_by_fkey;
alter table public.ops_engagement_checks add constraint ops_engagement_checks_updated_by_fkey
  foreign key (updated_by) references public.team_members(id) on delete set null not valid;
alter table public.ops_engagement_events drop constraint if exists ops_engagement_events_actor_id_fkey;
alter table public.ops_engagement_events add constraint ops_engagement_events_actor_id_fkey
  foreign key (actor_id) references public.team_members(id) on delete set null not valid;
alter table public.ops_engagements drop constraint if exists ops_engagements_created_by_fkey;
alter table public.ops_engagements add constraint ops_engagements_created_by_fkey
  foreign key (created_by) references public.team_members(id) on delete set null not valid;
alter table public.ops_engagements drop constraint if exists ops_engagements_manager_id_fkey;
alter table public.ops_engagements add constraint ops_engagements_manager_id_fkey
  foreign key (manager_id) references public.team_members(id) on delete set null not valid;
alter table public.ops_recurring_rules drop constraint if exists ops_recurring_rules_created_by_fkey;
alter table public.ops_recurring_rules add constraint ops_recurring_rules_created_by_fkey
  foreign key (created_by) references public.team_members(id) on delete set null not valid;
alter table public.ops_revisions drop constraint if exists ops_revisions_requested_by_fkey;
alter table public.ops_revisions add constraint ops_revisions_requested_by_fkey
  foreign key (requested_by) references public.team_members(id) on delete set null not valid;
alter table public.ops_task_checklist_items drop constraint if exists ops_task_checklist_items_completed_by_fkey;
alter table public.ops_task_checklist_items add constraint ops_task_checklist_items_completed_by_fkey
  foreign key (completed_by) references public.team_members(id) on delete set null not valid;
alter table public.ops_task_events drop constraint if exists ops_task_events_actor_id_fkey;
alter table public.ops_task_events add constraint ops_task_events_actor_id_fkey
  foreign key (actor_id) references public.team_members(id) on delete set null not valid;
alter table public.ops_task_links drop constraint if exists ops_task_links_created_by_fkey;
alter table public.ops_task_links add constraint ops_task_links_created_by_fkey
  foreign key (created_by) references public.team_members(id) on delete set null not valid;
alter table public.ops_tasks drop constraint if exists ops_tasks_created_by_fkey;
alter table public.ops_tasks add constraint ops_tasks_created_by_fkey
  foreign key (created_by) references public.team_members(id) on delete set null not valid;
alter table public.ops_tasks drop constraint if exists ops_tasks_manager_id_fkey;
alter table public.ops_tasks add constraint ops_tasks_manager_id_fkey
  foreign key (manager_id) references public.team_members(id) on delete set null not valid;
alter table public.ops_tasks drop constraint if exists ops_tasks_rated_by_fkey;
alter table public.ops_tasks add constraint ops_tasks_rated_by_fkey
  foreign key (rated_by) references public.team_members(id) on delete set null not valid;
alter table public.ops_work_sessions drop constraint if exists ops_work_sessions_corrected_by_fkey;
alter table public.ops_work_sessions add constraint ops_work_sessions_corrected_by_fkey
  foreign key (corrected_by) references public.team_members(id) on delete set null not valid;
alter table public.ops_work_sessions drop constraint if exists ops_work_sessions_team_member_id_fkey;
alter table public.ops_work_sessions add constraint ops_work_sessions_team_member_id_fkey
  foreign key (team_member_id) references public.team_members(id) on delete cascade not valid;
alter table public.option_reviews drop constraint if exists option_reviews_undone_by_fkey;
alter table public.option_reviews add constraint option_reviews_undone_by_fkey
  foreign key (undone_by) references public.team_members(id) on delete set null not valid;
alter table public.outstation_trips drop constraint if exists outstation_trips_driver_id_fkey;
alter table public.outstation_trips add constraint outstation_trips_driver_id_fkey
  foreign key (driver_id) references public.team_members(id) on delete cascade not valid;
alter table public.personnel_records drop constraint if exists personnel_records_team_member_id_fkey;
alter table public.personnel_records add constraint personnel_records_team_member_id_fkey
  foreign key (team_member_id) references public.team_members(id) on delete cascade not valid;
alter table public.personnel_salaries drop constraint if exists personnel_salaries_team_member_id_fkey;
alter table public.personnel_salaries add constraint personnel_salaries_team_member_id_fkey
  foreign key (team_member_id) references public.team_members(id) on delete cascade not valid;
alter table public.rail_orders drop constraint if exists rail_orders_member_id_fkey;
alter table public.rail_orders add constraint rail_orders_member_id_fkey
  foreign key (member_id) references public.team_members(id) on delete cascade not valid;

/* Validated where no row points at nothing; one that does stays `not valid`
   and still checks every new row. */
do $$
declare k record;
begin
  for k in
    select c.conrelid::regclass as tbl, c.conname
      from pg_constraint c
     where c.connamespace = 'public'::regnamespace and c.contype = 'f' and not c.convalidated
       and c.conname = any (array[
    'bukku_links_gone_sent_by_fkey', 'bukku_send_claims_claimed_by_fkey', 'campaigns_invoice_claimed_by_fkey',
    'code_email_template_updated_by_fkey', 'creator_email_templates_updated_by_fkey', 'creator_emails_sent_by_fkey',
    'creator_pay_requests_decided_by_fkey', 'creator_sheet_settings_updated_by_fkey', 'departments_updated_by_fkey',
    'email_templates_updated_by_fkey', 'hiring_email_templates_updated_by_fkey', 'id_formats_updated_by_fkey',
    'ops_tasks_delayed_by_fkey', 'outstation_photos_removed_by_fkey', 'perf_events_actor_id_fkey',
    'personnel_records_requested_by_fkey', 'personnel_records_superior_id_fkey', 'personnel_records_updated_by_fkey',
    'personnel_salaries_updated_by_fkey', 'personnel_settings_updated_by_fkey', 'sm_report_post_links_linked_by_fkey',
    'sm_report_post_links_unlinked_by_fkey', 'system_emails_sent_by_fkey', 'team_emails_sent_by_fkey',
    'team_invites_caller_id_fkey', 'team_notices_sent_by_fkey', 'video_scripts_created_by_fkey',
    'ai_drafts_client_id_fkey', 'client_brands_client_id_fkey', 'client_document_deletions_client_id_fkey',
    'delete_requests_client_id_fkey', 'ops_month_invoices_client_id_fkey', 'sm_reports_label_client_fkey',
    'system_emails_client_id_fkey', 'team_emails_client_id_fkey', 'wa_outbox_client_id_fkey',
    'creator_emails_again_of_fkey', 'creator_pay_requests_prior_id_fkey', 'hiring_docs_replaces_fkey',
    'system_emails_again_of_fkey', 'ai_drafts_script_id_fkey', 'ops_notifications_script_id_fkey',
    'supplier_emails_document_id_fkey', 'ops_recurring_made_source_task_id_fkey', 'sm_report_post_links_task_id_fkey',
    'ops_tasks_delayed_report_fkey', 'sm_report_post_links_report_id_fkey', 'ai_drafts_batch_id_fkey',
    'billing_entities_orphan_of_fkey', 'brand_analyses_press_id_fkey', 'client_entities_bill_contact_id_fkey',
    'creator_emails_creator_id_fkey', 'creator_emails_request_id_fkey', 'creator_emails_option_id_fkey',
    'ops_notifications_notice_id_fkey', 'ops_revisions_source_review_id_fkey', 'quotation_link_copies_quotation_id_fkey',
    'quotations_version_id_fkey', 'sm_report_post_links_post_id_fkey', 'system_emails_candidate_id_fkey',
    'team_emails_supplier_id_fkey', 'team_emails_template_id_fkey', 'delete_requests_kind_fkey',
    'perf_dept_scores_department_fkey', 'perf_people_department_fkey', 'mail_senders_box_fkey',
    'ops_recurring_rules_template_id_fkey', 'ops_tasks_template_id_fkey', 'ops_task_templates_workflow_id_fkey',
    'ops_tasks_workflow_id_fkey', 'client_services_quotation_id_fkey', 'clients_vic_by_fkey',
    'creator_pay_requests_entered_by_fkey', 'delete_requests_decided_by_fkey', 'delete_requests_requested_by_fkey',
    'guide_seen_team_member_id_fkey', 'invoice_send_template_updated_by_fkey', 'ops_due_requests_asked_by_fkey',
    'ops_due_requests_decided_by_fkey', 'ops_due_requests_decider_id_fkey', 'ops_engagement_checks_updated_by_fkey',
    'ops_engagement_events_actor_id_fkey', 'ops_engagements_created_by_fkey', 'ops_engagements_manager_id_fkey',
    'ops_recurring_rules_created_by_fkey', 'ops_revisions_requested_by_fkey', 'ops_task_checklist_items_completed_by_fkey',
    'ops_task_events_actor_id_fkey', 'ops_task_links_created_by_fkey', 'ops_tasks_created_by_fkey',
    'ops_tasks_manager_id_fkey', 'ops_tasks_rated_by_fkey', 'ops_work_sessions_corrected_by_fkey',
    'ops_work_sessions_team_member_id_fkey', 'option_reviews_undone_by_fkey', 'outstation_trips_driver_id_fkey',
    'personnel_records_team_member_id_fkey', 'personnel_salaries_team_member_id_fkey', 'rail_orders_member_id_fkey'])
  loop
    begin
      execute format('alter table %s validate constraint %I', k.tbl, k.conname);
    exception when foreign_key_violation then
      raise notice '% stays not valid: rows point at nothing', k.conname;
    end;
  end loop;
end $$;

-- END OF FOREIGN KEYS ON SINGLE-TARGET IDS ---------------------------------

select public.functions_tidy();
