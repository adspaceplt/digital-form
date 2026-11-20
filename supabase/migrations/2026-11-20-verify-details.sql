-- ===========================================================================
-- VERIFY DETAILS (2026-11-20)
-- ===========================================================================
-- WHY: the user approved the /verify/ revamp from its mockups (A1 to A6):
-- the first answer says only that ADSPACE PLT issued a document with this
-- reference; its days and steps are shown only to somebody holding the
-- copy, proved by the Document ID printed on every page of it.
--
-- WHAT IT CHANGES
--   * `doc_code` on `documents`, `client_documents`, `quotations`,
--     `hiring_docs` and `perf_reviews`: eight characters of the link
--     alphabet in upper case (23456789ABCDEFGHJKMNPQRSTUVWXYZ, from
--     gen_random_bytes), stamped on insert where none is given
--     (`doc_code_stamp`, `doc_code_new`), backfilled once, unique in each
--     table. Printed XXXX-XXXX as Document ID on every page.
--   * `doc_code_of(p_kind, p_id)` (anon too): the code of a document whose
--     id the caller holds, for the page that draws it. An id is a uuid
--     nobody can guess, and a sealed copy already prints it.
--   * `verify_find` (no caller's): the one lookup and the one state of a
--     reference, with its steps; `verify_serial` and `verify_details` read it.
--   * `verify_serial` answers found, the reference, the kind, the state, the
--     month of issue, whether a sealed copy is held, `more` and `by_day`
--     (the issue date may stand for the Document ID). No days, no Document
--     ID. Its 30 an hour and every refusal are kept.
--   * `verify_details(p_serial, p_code, p_day)` (anon): the day of issue,
--     the Document ID, the state and the steps by day, only for the
--     Document ID (a sealed quotation's or offer's earlier uuid too), or for
--     the day of issue of a document issued before `verify_code_from` (a
--     Business setting, YYYYMMDD) or holding no Document ID. One answer for
--     a wrong code, a wrong day and an unknown reference (`no_match`). Ten
--     an hour a connection (`verify_detail_tries`, RLS on, no policy, no
--     grant; a colleague and a session with no request not counted), then
--     `locked` with the minutes. Every answer names `contact`, the Legal and
--     compliance mailbox. Never a name, a term, a figure or a recipient.
--   * A sixth company mailbox, Legal and compliance
--     (legal@adspacestudios.com, `mail_boxes` key `legal`); `mail_boxes_set`
--     and `mail_senders_read` list it.
--   * `app_settings_set` takes `verify_code_from` (Document IDs printed from).
--   * `privacy_retention` lets go of a connection's detail count 30 days
--     after its hour began, as it does /verify/'s.
--
-- ORDER: 2026-10-07-function-hygiene.sql again (its `open_to_anon` now
-- names `verify_details` and `doc_code_of`), then the pages, then this file.
-- An old open page asks `verify_serial` and reads the new answer: the
-- reference, the kind and the state, with no days (it draws the month as
-- nothing). The new page meeting the old database draws the first answer
-- from `issued_at` and, with no `more`, offers no details. Safe to run twice.
--
-- ROLLBACK: run `verify_serial` from HR DOCUMENTS VERIFIED,
-- `privacy_retention` from VERIFY LOOKUPS COUNTED, and `mail_senders_read`
-- and `mail_boxes_set` from HIRING BEFORE THE FIRST HIRE again; drop
-- `verify_details`, `verify_detail_count`, `verify_find`, `verify_steps`,
-- `verify_by_day`, `doc_code_of`, the `doc_code_stamp` triggers and
-- `doc_code_stamp`, `doc_code_new` and `verify_detail_tries`; delete the
-- `legal` box and restore the five-key check; delete the setting and run
-- `app_settings_set` from INTERVIEW HELD again. The
-- columns may stay (a printed Document ID keeps its meaning).
-- ===========================================================================

-- A Document ID: eight characters of the link alphabet in upper case, from a
-- strong source, free in its table.
create or replace function public.doc_code_new(p_table text)
returns text language plpgsql volatile set search_path = public, extensions as $$
declare
  alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  v_out   text;
  v_bytes bytea;
  v_i     integer;
  v_b     integer;
  v_taken boolean;
begin
  if p_table not in ('documents', 'client_documents', 'quotations', 'hiring_docs', 'perf_reviews') then
    raise exception 'bad-table';
  end if;
  loop
    v_out := '';
    while length(v_out) < 8 loop
      v_bytes := gen_random_bytes(16);
      for v_i in 0..15 loop
        v_b := get_byte(v_bytes, v_i);
        /* 248 is 31 × 8: below it every character is equally likely. */
        if v_b < 248 and length(v_out) < 8 then
          v_out := v_out || substr(alphabet, 1 + (v_b % 31), 1);
        end if;
      end loop;
    end loop;
    execute format('select exists (select 1 from public.%I x where x.doc_code = $1)', p_table) into v_taken using v_out;
    exit when not v_taken;
  end loop;
  return v_out;
end $$;
revoke all on function public.doc_code_new(text) from public, anon, authenticated;

alter table public.documents        add column if not exists doc_code text;
alter table public.client_documents add column if not exists doc_code text;
alter table public.quotations       add column if not exists doc_code text;
alter table public.hiring_docs      add column if not exists doc_code text;
alter table public.perf_reviews     add column if not exists doc_code text;
create unique index if not exists documents_doc_code_idx        on public.documents (doc_code) where doc_code is not null;
create unique index if not exists client_documents_doc_code_idx on public.client_documents (doc_code) where doc_code is not null;
create unique index if not exists quotations_doc_code_idx       on public.quotations (doc_code) where doc_code is not null;
create unique index if not exists hiring_docs_doc_code_idx      on public.hiring_docs (doc_code) where doc_code is not null;
create unique index if not exists perf_reviews_doc_code_idx     on public.perf_reviews (doc_code) where doc_code is not null;
grant select (doc_code) on table public.quotations to authenticated;

/* Stamped on insert where none is given. Security definer: the generator is
   closed to every caller (a trigger calling it as the colleague failed,
   2026-11-09). */
create or replace function public.doc_code_stamp()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.doc_code is null then new.doc_code := public.doc_code_new(tg_table_name); end if;
  return new;
end $$;
revoke all on function public.doc_code_stamp() from public, anon, authenticated;
create or replace trigger doc_code_stamp before insert on public.documents        for each row execute function public.doc_code_stamp();
create or replace trigger doc_code_stamp before insert on public.client_documents for each row execute function public.doc_code_stamp();
create or replace trigger doc_code_stamp before insert on public.quotations       for each row execute function public.doc_code_stamp();
create or replace trigger doc_code_stamp before insert on public.hiring_docs      for each row execute function public.doc_code_stamp();
create or replace trigger doc_code_stamp before insert on public.perf_reviews     for each row execute function public.doc_code_stamp();

/* Every document issued before this release takes its code once. The
   tables' own update triggers (a lead moved by a sent quotation, a scope
   guard) stand aside for the backfill alone: it changes nothing they
   watch, and each is put back as it was. */
do $$
declare
  t text;
  g record;
  v_off text[];
  v_none boolean;
begin
  foreach t in array array['documents', 'client_documents', 'quotations', 'hiring_docs', 'perf_reviews'] loop
    execute format('select not exists (select 1 from public.%I x where x.doc_code is null)', t) into v_none;
    continue when v_none;
    v_off := '{}';
    for g in select tg.tgname from pg_trigger tg
              where tg.tgrelid = ('public.' || t)::regclass and not tg.tgisinternal and tg.tgenabled = 'O'
    loop
      execute format('alter table public.%I disable trigger %I', t, g.tgname);
      v_off := v_off || g.tgname::text;
    end loop;
    execute format('update public.%I x set doc_code = public.doc_code_new(%L) where x.doc_code is null', t, t);
    foreach g.tgname in array v_off loop
      execute format('alter table public.%I enable trigger %I', t, g.tgname);
    end loop;
  end loop;
end $$;

/* The code of a document whose id the caller holds, as printed. */
create or replace function public.doc_code_of(p_kind text, p_id uuid)
returns text
language plpgsql stable security definer set search_path = public as $$
declare v text;
begin
  if p_id is null then return null; end if;
  v := case p_kind
    when 'document'  then (select x.doc_code from public.documents x where x.id = p_id)
    when 'letter'    then (select x.doc_code from public.client_documents x where x.id = p_id)
    when 'quotation' then (select x.doc_code from public.quotations x where x.id = p_id)
    when 'hiring'    then (select x.doc_code from public.hiring_docs x where x.id = p_id)
    when 'perf'      then (select x.doc_code from public.perf_reviews x where x.id = p_id)
  end;
  if v is null then return null; end if;
  return substr(v, 1, 4) || '-' || substr(v, 5, 4);
end $$;
revoke all on function public.doc_code_of(text, uuid) from public;
grant execute on function public.doc_code_of(text, uuid) to anon, authenticated;

/* The first day every copy carries its Document ID (YYYYMMDD): a document
   issued before it may be proved by its day of issue instead. */
insert into public.app_settings (key, from_date, value)
select 'verify_code_from', date '2023-08-14', 20261120
 where not exists (select 1 from public.app_settings s where s.key = 'verify_code_from');

/* `verify_code_from` is a Business setting the team may move (a day as
   YYYYMMDD, 14 Aug 2023 to 31 Dec 2099): app_settings_set as INTERVIEW
   HELD left it, taking it too. */
create or replace function public.app_settings_set(p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members; v_k text; v_v numeric; v_was numeric; v_name text; v_unit text; v_pre text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_keys constant text[] := array['lead_followup_hours', 'proposal_followup_days', 'sst_pct',
    'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_18_23', 'term_24', 'report_due_days', 'revision_due_days',
    'ai_price_in', 'ai_price_out', 'meta_checks', 'approval_reminder_days', 'ai_price_search',
    'reach_allowance_pct', 'priority_urgent_hours', 'priority_high_hours', 'priority_medium_hours',
    'task_remind_hours', 'task_start_days', 'quote_valid_days', 'details_form_days', 'wa_repeat_hours',
    'bench_cpr_low', 'bench_cpr_mid', 'bench_cpr_high', 'bench_cpr_top', 'bench_msg_min', 'bench_msg_target', 'bench_msg_max',
    'bench_form_min', 'bench_form_target', 'bench_form_max', 'bench_cpm_min', 'bench_cpm_max', 'bench_cpl_rise',
    'bench_reels_share', 'bench_ad_spend_pct', 'bench_adset_daily', 'vic_lead_followup_hours', 'vic_proposal_followup_days', 'fx_sgd',
    'health_keep_months', 'health_leaver_months', 'abroad_days', 'abroad_remind_hours', 'analytics_from',
    'analytics_change_pct', 'analytics_churn_pct', 'quote_reply_days', 'quote_wa_day', 'client_email_on', 'ai_price_image', 'report_post_links',
    'creator_pay_days_myr', 'creator_pay_days_other', 'task_past_days', 'hiring_invite_days', 'hiring_link_days', 'hiring_pool_months', 'hiring_keep_months', 'plan_db_mb', 'plan_db_alert_pct',
    'timely_pct', 'timely_late_days', 'stage_back_days', 'hiring_reply_days', 'session_idle_days', 'hiring_decision_days', 'verify_code_from'];
  v_moved text[] := '{}';
  v_drop boolean; v_fw text; v_fv text;
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  if p_from is null or p_from < v_today then return jsonb_build_object('error', 'past', 'today', v_today); end if;
  if jsonb_typeof(p_values) is distinct from 'object' then return jsonb_build_object('error', 'bad-value'); end if;
  for v_k in select jsonb_object_keys(p_values) loop
    if not (v_k = any(v_keys)) or jsonb_typeof(p_values -> v_k) <> 'number' then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
    v_v := (p_values ->> v_k)::numeric;
    if round(v_v, case when v_k = 'fx_sgd' then 4 else 2 end) <> v_v
       or (v_k = 'fx_sgd' and (v_v < 0.5 or v_v > 10))
       or (v_k in ('lead_followup_hours', 'vic_lead_followup_hours') and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k in ('proposal_followup_days', 'vic_proposal_followup_days') and (v_v < 1 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'report_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'revision_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'approval_reminder_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'sst_pct' and (v_v < 0 or v_v > 100))
       or (v_k like 'term_%' and (v_v < -100 or v_v > 100))
       or (v_k like 'ai_price_%' and (v_v < 0 or v_v > 1000))
       or (v_k in ('meta_checks', 'client_email_on', 'report_post_links') and v_v not in (0, 1))
       or (v_k = 'reach_allowance_pct' and (v_v < 0 or v_v > 5))
       or (v_k like 'priority_%_hours' and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k = 'task_remind_hours' and (v_v < 0 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'task_start_days' and (v_v < 0 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'task_past_days' and (v_v < 0 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_invite_days' and (v_v < 1 or v_v > 14 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_link_days' and (v_v < 7 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_pool_months' and (v_v < 1 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_keep_months' and (v_v < 1 or v_v > 36 or v_v <> trunc(v_v)))
       or (v_k = 'plan_db_mb' and (v_v < 100 or v_v > 1000000 or v_v <> trunc(v_v)))
       or (v_k = 'plan_db_alert_pct' and (v_v < 10 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k = 'timely_pct' and (v_v < 1 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k = 'timely_late_days' and (v_v < 0 or v_v > 30 or round(v_v, 1) <> v_v))
       or (v_k = 'stage_back_days' and (v_v < 0 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_reply_days' and (v_v < 1 or v_v > 14 or v_v <> trunc(v_v)))
       or (v_k = 'session_idle_days' and (v_v < 0 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_decision_days' and (v_v < 1 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k in ('quote_valid_days', 'details_form_days') and (v_v < 1 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'quote_reply_days' and (v_v < 1 or v_v > 10 or v_v <> trunc(v_v)))
       or (v_k in ('creator_pay_days_myr', 'creator_pay_days_other') and (v_v < 1 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'wa_repeat_hours' and (v_v < 0 or v_v > 168 or v_v <> trunc(v_v)))
       or (v_k = 'quote_wa_day' and (v_v < 0 or v_v > 500 or v_v <> trunc(v_v)))
       or (v_k = 'health_keep_months' and (v_v < 6 or v_v > 120 or v_v <> trunc(v_v)))
       or (v_k = 'health_leaver_months' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'abroad_days' and (v_v < 1 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'abroad_remind_hours' and (v_v < 0 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'analytics_from' and (v_v < 202308 or v_v > 209912 or v_v <> trunc(v_v) or mod(v_v, 100) not between 1 and 12))
       or (v_k = 'verify_code_from' and (v_v < 20230814 or v_v > 20991231 or v_v <> trunc(v_v) or mod(v_v, 100) not between 1 and 31 or mod(trunc(v_v / 100), 100) not between 1 and 12))
       or (v_k = 'analytics_change_pct' and (v_v < 1 or v_v > 50 or v_v <> trunc(v_v)))
       or (v_k = 'analytics_churn_pct' and (v_v < 1 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k in ('bench_reels_share') and (v_v < 0 or v_v > 100))
       or (v_k = 'bench_ad_spend_pct' and (v_v < 1 or v_v > 100))
       or (v_k = 'bench_cpl_rise' and (v_v < -100 or v_v > 100))
       or (v_k like 'bench_%' and v_k not in ('bench_reels_share', 'bench_ad_spend_pct', 'bench_cpl_rise') and (v_v < 0 or v_v > 10000)) then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
  end loop;
  for v_k in select jsonb_object_keys(p_values) loop
    v_v := (p_values ->> v_k)::numeric;
    v_was := public.app_setting(v_k, p_from);
    if v_was is distinct from v_v then
      /* A planned change saved back to the value in force the day before is
         withdrawn: its row goes, rather than a second row restating it. */
      v_drop := p_from > v_today
        and exists (select 1 from public.app_settings s where s.key = v_k and s.from_date = p_from)
        and exists (select 1 from public.app_settings s where s.key = v_k and s.from_date < p_from)
        and public.app_setting(v_k, p_from - 1) = v_v;
      if v_drop then
        delete from public.app_settings s where s.key = v_k and s.from_date = p_from;
      else
        insert into public.app_settings (key, from_date, value, set_by, set_at)
        values (v_k, p_from, v_v, v_me.id, now())
        on conflict (key, from_date) do update set value = excluded.value, set_by = excluded.set_by, set_at = now();
      end if;
      v_name := case v_k when 'lead_followup_hours' then 'Lead follow-up limit' when 'proposal_followup_days' then 'Proposal follow-up limit'
        when 'vic_lead_followup_hours' then 'VIC lead follow-up limit' when 'vic_proposal_followup_days' then 'VIC proposal follow-up limit'
        when 'sst_pct' then 'SST' when 'term_1_3' then 'Under 3 months' when 'term_4_5' then '3-month commitment'
        when 'term_6_11' then '6-month commitment' when 'term_12_23' then '12-month commitment' when 'term_18_23' then '18-month commitment' when 'term_24' then '24-month commitment'
        when 'revision_due_days' then 'Revision due' when 'ai_price_in' then 'AI input price per million tokens'
        when 'ai_price_out' then 'AI output price per million tokens' when 'ai_price_search' then 'AI web search price per thousand searches' when 'ai_price_image' then 'AI price per scene picture' when 'meta_checks' then 'Meta checks' when 'client_email_on' then 'Send by email' when 'report_post_links' then 'Posts linked to tasks'
        when 'approval_reminder_days' then 'Approval reminder' when 'reach_allowance_pct' then 'Reach allowance'
        when 'priority_urgent_hours' then 'Urgent deadline' when 'priority_high_hours' then 'High deadline'
        when 'priority_medium_hours' then 'Medium deadline' when 'task_remind_hours' then 'Task reminders'
        when 'task_start_days' then 'Not started reminder' when 'task_past_days' then 'Past dates on new tasks' when 'hiring_invite_days' then 'Interview times within' when 'hiring_link_days' then 'Candidate link open' when 'hiring_pool_months' then 'Talent pool kept' when 'hiring_keep_months' then 'Closed candidates kept' when 'quote_valid_days' then 'Quotation validity' when 'details_form_days' then 'Details form open'
        when 'quote_reply_days' then 'Contact within'
        when 'plan_db_mb' then 'Database plan' when 'plan_db_alert_pct' then 'Database alert'
        when 'timely_pct' then 'On time or early target' when 'timely_late_days' then 'Average lateness target'
        when 'stage_back_days' then 'Past dates on stage moves'
        when 'hiring_reply_days' then 'Interview reply time'
        when 'session_idle_days' then 'Signed-in devices'
        when 'hiring_decision_days' then 'Decision time'
        when 'creator_pay_days_myr' then 'Creator payment in MYR' when 'creator_pay_days_other' then 'Creator payment in other currencies'
        when 'wa_repeat_hours' then 'WhatsApp sent again'
        when 'quote_wa_day' then 'Website quotations on WhatsApp'
        when 'bench_cpr_low' then 'Property cost per result, tier 1 from' when 'bench_cpr_mid' then 'Property cost per result, tier 2 from'
        when 'bench_cpr_high' then 'Property cost per result, tier 3 from' when 'bench_cpr_top' then 'Property cost per result, tier 3 up to'
        when 'bench_msg_min' then 'Messaging cost per result, low' when 'bench_msg_target' then 'Messaging cost per result, target'
        when 'bench_msg_max' then 'Messaging cost per result, high' when 'bench_form_min' then 'Lead form cost per result, low'
        when 'bench_form_target' then 'Lead form cost per result, target' when 'bench_form_max' then 'Lead form cost per result, high'
        when 'bench_cpm_min' then 'Cost per 1,000 impressions, low' when 'bench_cpm_max' then 'Cost per 1,000 impressions, high'
        when 'bench_cpl_rise' then 'Yearly rise in cost per lead' when 'bench_reels_share' then 'Reels share of impressions'
        when 'bench_ad_spend_pct' then 'Ad spend share of the budget' when 'bench_adset_daily' then 'Minimum daily budget per ad set'
        when 'fx_sgd' then 'Singapore dollar rate'
        when 'health_keep_months' then 'Health check-ins kept' when 'health_leaver_months' then 'Leavers'' health data kept'
        when 'abroad_days' then 'Overseas approval' when 'abroad_remind_hours' then 'Overseas reminder'
        when 'analytics_from' then 'Analytics counts from'
        when 'verify_code_from' then 'Document IDs printed from'
        when 'analytics_change_pct' then 'Analytics change threshold' when 'analytics_churn_pct' then 'Analytics quarterly churn alert'
        else 'Report due' end;
      v_pre := case when v_k = 'fx_sgd' then 'RM ' when v_k like 'ai_price_%' then 'US$' when v_k like 'bench_%' and v_k not in ('bench_cpl_rise', 'bench_reels_share', 'bench_ad_spend_pct') then 'RM ' else '' end;
      v_unit := case when v_k = 'fx_sgd' then ' per S$1' when v_k in ('lead_followup_hours', 'vic_lead_followup_hours', 'task_remind_hours', 'wa_repeat_hours', 'abroad_remind_hours') or v_k like 'priority_%_hours' then ' hours'
        when v_k in ('proposal_followup_days', 'vic_proposal_followup_days', 'report_due_days', 'revision_due_days', 'approval_reminder_days', 'task_start_days', 'task_past_days', 'quote_valid_days', 'details_form_days', 'abroad_days', 'hiring_invite_days', 'hiring_link_days', 'timely_late_days', 'stage_back_days', 'hiring_reply_days', 'session_idle_days') then ' days'
        when v_k in ('quote_reply_days', 'creator_pay_days_myr', 'creator_pay_days_other', 'hiring_decision_days') then ' working days'
        when v_k = 'quote_wa_day' then ' per day'
        when v_k = 'plan_db_mb' then ' MB'
        when v_k in ('health_keep_months', 'hiring_pool_months', 'hiring_keep_months', 'health_leaver_months') then ' months'
        when v_pre <> '' then '' else '%' end;
      v_fw := case when v_k in ('meta_checks', 'client_email_on', 'report_post_links') then case when v_was = 1 then 'On' else 'Off' end
              when v_k = 'analytics_from' then coalesce(substr(public.register_day(to_date(v_was::bigint::text, 'YYYYMM')), 3), 'not set') else coalesce(v_pre ||
              trim(to_char(v_was, case when v_k = 'fx_sgd' then 'FM999999990.9999' else 'FM999999990.99' end), '.') || v_unit, 'not set') end;
      v_fv := case when v_k in ('meta_checks', 'client_email_on', 'report_post_links') then case when v_v = 1 then 'On' else 'Off' end
              when v_k = 'analytics_from' then substr(public.register_day(to_date(v_v::bigint::text, 'YYYYMM')), 3) else v_pre ||
              trim(to_char(v_v, case when v_k = 'fx_sgd' then 'FM999999990.9999' else 'FM999999990.99' end), '.') || v_unit end;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(v_me.name, 'admin'), 'team.changed', 'Settings',
              case when v_drop then v_name || ': planned change withdrawn · ' || v_fw || ' from ' || public.register_day(p_from) ||
                ', stays ' || v_fv else
              case when v_k = 'analytics_from' then v_name || ': ' || v_fw || ' → ' || v_fv || ' · from ' || public.register_day(p_from) else
              v_name || ': ' || case when v_k in ('meta_checks', 'client_email_on', 'report_post_links') then
                case when v_was = 1 then 'On' else 'Off' end || ' → ' || case when v_v = 1 then 'On' else 'Off' end ||
                ' · from ' || public.register_day(p_from) else '' end ||
              case when v_k in ('meta_checks', 'client_email_on', 'report_post_links') then '' else coalesce(v_pre ||
              trim(to_char(v_was, case when v_k = 'fx_sgd' then 'FM999999990.9999' else 'FM999999990.99' end), '.') || v_unit, 'not set') || ' → ' || v_pre ||
              trim(to_char(v_v, case when v_k = 'fx_sgd' then 'FM999999990.9999' else 'FM999999990.99' end), '.') || v_unit ||
              ' · from ' || public.register_day(p_from) end end end);
      v_moved := v_moved || v_k;
    end if;
  end loop;
  return public.app_settings_read() || jsonb_build_object('changed', to_jsonb(v_moved));
end $$;
revoke all on function public.app_settings_set(date, jsonb) from public, anon;
grant execute on function public.app_settings_set(date, jsonb) to authenticated;

/* A reference's steps, by day, those with no day left out. */
create or replace function public.verify_steps(p jsonb)
returns jsonb language sql immutable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('day', e ->> 'day', 'step', e ->> 'step') order by (e ->> 'day')::date, n), '[]'::jsonb)
    from jsonb_array_elements(coalesce(p, '[]'::jsonb)) with ordinality as t(e, n)
   where e ->> 'day' is not null;
$$;
revoke all on function public.verify_steps(jsonb) from public, anon, authenticated;

/* The one lookup of a reference: the standing version first, a reference
   typed with dashes for slashes the same reference, an exact match first.
   Answers what each answer may draw from, never a person, a term or a
   figure. Run inside the anon functions that read it, never alone. */
create or replace function public.verify_find(p_serial text)
returns jsonb
language plpgsql stable set search_path = public as $$
declare
  s text := upper(btrim(coalesce(p_serial, '')));
  sd text;
  d public.documents%rowtype;
  l public.client_documents%rowtype;
  q public.quotations%rowtype;
  h public.hiring_docs%rowtype;
  rv public.perf_reviews%rowtype;
  dl public.perf_deleted%rowtype;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_state text;
  v_rep date;
begin
  if length(s) < 3 or length(s) > 40 then return null; end if;
  sd := replace(s, '/', '-');
  select * into d from public.documents x
   where upper(x.serial) = s or replace(upper(x.serial), '/', '-') = sd
   order by (upper(x.serial) = s) desc, (x.voided_at is null) desc, x.created_at desc limit 1;
  if d.id is not null then
    return jsonb_build_object('src', 'document', 'id', d.id, 'serial', d.serial,
      'kind', case when d.family = 'hr' then 'HR Letter' else d.kind end,
      'issued', d.issued_at, 'code', d.doc_code, 'sealed', false,
      'state', case when d.voided_at is null then 'valid' else 'voided' end,
      'steps', public.verify_steps(jsonb_build_array(
        jsonb_build_object('step', 'issued', 'day', d.issued_at),
        jsonb_build_object('step', 'voided', 'day', (d.voided_at at time zone 'Asia/Kuala_Lumpur')::date))));
  end if;
  select * into l from public.client_documents x
   where upper(x.number) = s or replace(upper(x.number), '/', '-') = sd
   order by (upper(x.number) = s) desc limit 1;
  if l.id is not null then
    select x.issued_at into v_rep
      from public.client_documents x where x.id = l.superseded_by;
    return jsonb_build_object('src', 'letter', 'id', l.id, 'serial', l.number, 'kind', 'Letter of Offer',
      'issued', l.issued_at, 'code', l.doc_code, 'sealed', false,
      'state', case when l.voided_at is not null then 'voided'
                    when l.superseded_by is not null then 'replaced'
                    else 'valid' end,
      'steps', public.verify_steps(jsonb_build_array(
        jsonb_build_object('step', 'issued', 'day', l.issued_at),
        jsonb_build_object('step', 'signed', 'day', (l.signed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'confirmed', 'day', (l.verified_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'replaced', 'day', v_rep),
        jsonb_build_object('step', 'voided', 'day', (l.voided_at at time zone 'Asia/Kuala_Lumpur')::date))));
  end if;
  select * into q from public.quotations x
   where (upper(x.ref) = s or replace(upper(x.ref), '/', '-') = sd)
     and (x.sent_out_at is not null or x.signed_at is not null)
   order by (upper(x.ref) = s) desc, x.issued_at desc limit 1;
  if q.id is not null then
    select (min(r.issued_at) at time zone 'Asia/Kuala_Lumpur')::date into v_rep
      from public.quotations r where r.replaces = q.id and r.removed_at is null;
    v_state := case when q.withdrawn_at is not null then 'withdrawn'
                    when q.status = 'not_proceeding' or q.removed_at is not null then 'voided'
                    when v_rep is not null then 'replaced'
                    when q.signed_at is null and q.valid_until is not null and q.valid_until < v_today then 'expired'
                    else 'valid' end;
    return jsonb_build_object('src', 'quotation', 'id', q.id, 'serial', q.ref, 'kind', 'Quotation',
      'issued', (q.issued_at at time zone 'Asia/Kuala_Lumpur')::date, 'code', q.doc_code, 'sealed', q.seal_key is not null,
      'state', v_state,
      'steps', public.verify_steps(jsonb_build_array(
        jsonb_build_object('step', 'issued', 'day', (q.issued_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'sent', 'day', (q.sent_out_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'signed', 'day', (q.signed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'confirmed', 'day', (q.reviewed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'sealed', 'day', (q.sealed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'declined', 'day', (q.declined_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'withdrawn', 'day', q.withdrawn_on),
        jsonb_build_object('step', 'voided', 'day', (q.removed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'replaced', 'day', v_rep),
        jsonb_build_object('step', 'expired', 'day', case when v_state = 'expired' then q.valid_until + 1 end))));
  end if;
  /* An offer or a contract once sent: the version standing first (a
     replacement keeps the reference, the one it replaced void). */
  select * into h from public.hiring_docs x
   where (upper(x.serial) = s or replace(upper(x.serial), '/', '-') = sd)
     and x.sent_at is not null and x.state <> 'draft'
   order by (upper(x.serial) = s) desc, (x.state <> 'void') desc, x.sent_at desc limit 1;
  if h.id is not null then
    v_state := case when h.state = 'void' then 'voided'
                    when h.state = 'withdrawn' then 'withdrawn'
                    when h.state = 'declined' then 'declined'
                    when h.state = 'sent' and h.reply_by is not null and h.reply_by < now() then 'expired'
                    else 'valid' end;
    return jsonb_build_object('src', 'hiring', 'id', h.id, 'serial', h.serial, 'kind', 'HR Letter',
      'issued', (h.sent_at at time zone 'Asia/Kuala_Lumpur')::date, 'code', h.doc_code, 'sealed', h.seal_sha is not null,
      'state', v_state,
      'steps', public.verify_steps(jsonb_build_array(
        jsonb_build_object('step', 'issued', 'day', (h.sent_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'signed', 'day', (h.signed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'confirmed', 'day', (h.confirmed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'sealed', 'day', (h.sealed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'declined', 'day', case when h.state = 'declined' then (coalesce(h.answered_at, h.updated_at) at time zone 'Asia/Kuala_Lumpur')::date end),
        jsonb_build_object('step', 'withdrawn', 'day', case when h.state = 'withdrawn' then (h.updated_at at time zone 'Asia/Kuala_Lumpur')::date end),
        jsonb_build_object('step', 'voided', 'day', (h.voided_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'expired', 'day', case when v_state = 'expired' then (h.reply_by at time zone 'Asia/Kuala_Lumpur')::date end))));
  end if;
  select * into rv from public.perf_reviews pr
   where (upper(pr.serial) = s or replace(upper(pr.serial), '/', '-') = sd)
     and exists (select 1 from public.perf_events pe where pe.review_id = pr.id and pe.kind = 'printed')
   limit 1;
  if rv.id is not null then
    return jsonb_build_object('src', 'perf', 'id', rv.id, 'serial', rv.serial, 'kind', 'HR Letter',
      'issued', (rv.released_at at time zone 'Asia/Kuala_Lumpur')::date, 'code', rv.doc_code, 'sealed', false,
      'state', case when rv.status = 'draft' then 'replaced' else 'valid' end,
      'steps', public.verify_steps(jsonb_build_array(
        jsonb_build_object('step', 'issued', 'day', (rv.released_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'acknowledged', 'day', (rv.acknowledged_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'finalised', 'day', (rv.finalised_at at time zone 'Asia/Kuala_Lumpur')::date))));
  end if;
  select * into dl from public.perf_deleted pd
   where pd.printed and (upper(pd.serial) = s or replace(upper(pd.serial), '/', '-') = sd)
   order by pd.deleted_at desc limit 1;
  if dl.id is not null then
    return jsonb_build_object('src', 'perf_deleted', 'id', dl.id, 'serial', dl.serial, 'kind', 'HR Letter',
      'issued', (dl.released_at at time zone 'Asia/Kuala_Lumpur')::date, 'code', null, 'sealed', false, 'state', 'voided',
      'steps', public.verify_steps(jsonb_build_array(
        jsonb_build_object('step', 'issued', 'day', (dl.released_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'voided', 'day', (dl.deleted_at at time zone 'Asia/Kuala_Lumpur')::date))));
  end if;
  return null;
end $$;
revoke all on function public.verify_find(text) from public, anon, authenticated;

/* The day of issue may stand for the Document ID: a document issued before
   every copy carried one (`verify_code_from`), or one that holds none. */
create or replace function public.verify_by_day(f jsonb)
returns boolean language plpgsql stable set search_path = public as $$
declare
  v_from numeric := public.app_setting('verify_code_from', (now() at time zone 'Asia/Kuala_Lumpur')::date);
begin
  if f is null or f ->> 'issued' is null then return false; end if;
  if f ->> 'code' is null then return true; end if;
  if v_from is null then return false; end if;
  return (f ->> 'issued')::date < to_date(v_from::bigint::text, 'YYYYMMDD');
end $$;
revoke all on function public.verify_by_day(jsonb) from public, anon, authenticated;

/* The first answer: that ADSPACE PLT issued a document with this reference,
   its kind, its standing and its month. Its days and steps wait for the
   Document ID (`verify_details`). */
create or replace function public.verify_serial(p_serial text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  f jsonb;
  v_wait integer := public.verify_count();
begin
  if v_wait > 0 then
    return jsonb_build_object('found', false, 'locked', true, 'minutes', v_wait);
  end if;
  f := public.verify_find(p_serial);
  if f is null then return jsonb_build_object('found', false); end if;
  return jsonb_build_object('found', true, 'serial', f ->> 'serial', 'kind', f ->> 'kind', 'state', f ->> 'state',
    'issued_month', to_char((f ->> 'issued')::date, 'YYYY-MM'), 'sealed', coalesce((f ->> 'sealed')::boolean, false),
    'more', true, 'by_day', public.verify_by_day(f));
end $$;
revoke all on function public.verify_serial(text) from public;
grant execute on function public.verify_serial(text) to anon, authenticated;

/* Ten detail checks an hour from one connection the team does not hold. */
create table if not exists public.verify_detail_tries (
  ip    text primary key,
  n     integer not null default 0,
  since timestamptz not null default now()
);
alter table public.verify_detail_tries enable row level security;
revoke all on public.verify_detail_tries from public, anon, authenticated;

create or replace function public.verify_detail_count()
returns integer
language plpgsql volatile set search_path = public as $$
declare
  v_ip text := public.request_ip();
  v_n integer;
  v_since timestamptz;
begin
  if v_ip = '' or public.is_team() then return 0; end if;
  insert into public.verify_detail_tries as v (ip, n, since) values (v_ip, 1, now())
  on conflict (ip) do update
    set n = case when v.since < now() - interval '1 hour' then 1 else v.n + 1 end,
        since = case when v.since < now() - interval '1 hour' then now() else v.since end
  returning v.n, v.since into v_n, v_since;
  if v_n > 10 then
    return greatest(1, ceil(extract(epoch from (v_since + interval '1 hour' - now())) / 60)::integer);
  end if;
  return 0;
end $$;
revoke all on function public.verify_detail_count() from public, anon, authenticated;

/* The full answer for somebody holding the copy: the Document ID printed on
   it, or the day of issue where that may stand for it. One answer for a
   wrong code, a wrong day and an unknown reference. */
create or replace function public.verify_details(p_serial text, p_code text, p_day date)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  f jsonb;
  c text := upper(regexp_replace(left(coalesce(p_code, ''), 80), '[^0-9A-Za-z]', '', 'g'));
  v_contact text := (select b.address from public.mail_boxes b where b.key = 'legal');
  v_wait integer := public.verify_detail_count();
  v_ok boolean := false;
begin
  if v_wait > 0 then
    return jsonb_build_object('locked', true, 'minutes', v_wait, 'contact', v_contact);
  end if;
  f := public.verify_find(p_serial);
  if f is not null then
    if c <> '' and f ->> 'code' is not null and c = f ->> 'code' then
      v_ok := true;
    elsif c ~ '^[0-9A-F]{32}$' and (f ->> 'sealed')::boolean and f ->> 'src' in ('quotation', 'hiring')
          and c = upper(replace(f ->> 'id', '-', '')) then
      v_ok := true;
    elsif c = '' and p_day is not null and public.verify_by_day(f) and p_day = (f ->> 'issued')::date then
      v_ok := true;
    end if;
  end if;
  if not v_ok then return jsonb_build_object('no_match', true, 'contact', v_contact); end if;
  return jsonb_build_object('ok', true, 'serial', f ->> 'serial', 'kind', f ->> 'kind', 'state', f ->> 'state',
    'issued_on', f ->> 'issued',
    'document_id', case when f ->> 'code' is not null then substr(f ->> 'code', 1, 4) || '-' || substr(f ->> 'code', 5, 4) end,
    'sealed', coalesce((f ->> 'sealed')::boolean, false),
    'history', f -> 'steps', 'contact', v_contact);
end $$;
revoke all on function public.verify_details(text, text, date) from public;
grant execute on function public.verify_details(text, text, date) to anon, authenticated;

/* The Legal and compliance mailbox, named on /verify/ where a copy does not
   match: a sixth company mailbox, seeded once. */
alter table public.mail_boxes drop constraint if exists mail_boxes_key_check;
alter table public.mail_boxes add constraint mail_boxes_key_check check (key in ('general', 'hr', 'payables', 'finance', 'einvoice', 'legal'));
insert into public.mail_boxes (key, label, address) values ('legal', 'Legal and compliance', 'legal@adspacestudios.com') on conflict (key) do nothing;

create or replace function public.mail_senders_read()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_team() then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object(
    'boxes', (select jsonb_agg(jsonb_build_object('key', b.key, 'label', b.label, 'address', b.address)
                order by array_position(array['general', 'hr', 'payables', 'finance', 'einvoice', 'legal'], b.key)) from public.mail_boxes b),
    'senders', (select jsonb_object_agg(m.key, jsonb_build_object('from', m.name || ' <' || m.address || '>', 'reply_to', b.address))
                  from public.mail_senders m join public.mail_boxes b on b.key = m.box));
end $$;
revoke all on function public.mail_senders_read() from public, anon;
grant execute on function public.mail_senders_read() to authenticated;

create or replace function public.mail_boxes_set(p_values jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  b  public.mail_boxes;
  v  text;
  v_said text[] := '{}';
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  for b in select * from public.mail_boxes order by array_position(array['general', 'hr', 'payables', 'finance', 'einvoice', 'legal'], key) loop
    v := lower(btrim(coalesce(p_values ->> b.key, b.address)));
    if v !~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$' then return jsonb_build_object('error', 'bad-email', 'field', b.key); end if;
    if v is distinct from b.address then
      update public.mail_boxes x set address = v where x.key = b.key;
      v_said := v_said || (b.label || ': ' || b.address || ' → ' || v);
    end if;
  end loop;
  if array_length(v_said, 1) > 0 then
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.changed', 'Reply-to mailboxes', array_to_string(v_said, ' · '));
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.mail_boxes_set(jsonb) from public, anon;
grant execute on function public.mail_boxes_set(jsonb) to authenticated;

create or replace function public.privacy_retention(p_now timestamptz default now())
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_wa integer := 0; v_act integer := 0; v_hc integer := 0; v_hl integer := 0; v_lt integer := 0; v_vt integer := 0; v_vd integer := 0;
  v_today date := (p_now at time zone 'Asia/Kuala_Lumpur')::date;
  v_keep integer := coalesce(public.app_setting('health_keep_months', (p_now at time zone 'Asia/Kuala_Lumpur')::date), 24)::integer;
  v_left integer := coalesce(public.app_setting('health_leaver_months', (p_now at time zone 'Asia/Kuala_Lumpur')::date), 6)::integer;
  v_gone uuid[];
begin
  update public.wa_outbox o
     set to_number = '', to_name = null, params = '[]'::jsonb, button = null
   where o.created_at < p_now - interval '12 months'
     and o.state not in ('queued', 'sending')
     and (o.to_number <> '' or o.to_name is not null or o.params <> '[]'::jsonb or o.button is not null);
  get diagnostics v_wa = row_count;
  delete from public.activity_log a where a.created_at < p_now - interval '3 years';
  get diagnostics v_act = row_count;
  delete from public.health_checkins k where k.half < v_today - make_interval(months => v_keep);
  get diagnostics v_hc = row_count;
  select coalesce(array_agg(m.id), '{}') into v_gone from public.team_members m
   where not m.active and coalesce(m.removed_at, m.expired_at) < p_now - make_interval(months => v_left);
  if array_length(v_gone, 1) > 0 then
    delete from public.health_checkins k where k.team_member_id = any(v_gone);
    get diagnostics v_hl = row_count;
    delete from public.health_talks t where t.team_member_id = any(v_gone) or t.with_id = any(v_gone);
    delete from public.health_log l where l.team_member_id = any(v_gone);
    delete from public.health_consents c where c.team_member_id = any(v_gone);
  end if;
  -- A caller's address against a link's passcode, once it has had nothing
  -- to say for 30 days and holds no lock (audit 2026-10-18, item 14).
  delete from public.link_tries t
   where greatest(t.last_at, coalesce(t.ok_at, t.last_at)) < p_now - interval '30 days'
     and coalesce(t.locked_until, t.last_at) < p_now;
  get diagnostics v_lt = row_count;
  -- A caller's address against /verify/, once its hour began 30 days ago.
  delete from public.verify_tries v where v.since < p_now - interval '30 days';
  get diagnostics v_vt = row_count;
  -- And against /verify/'s details (VERIFY DETAILS, 2026-11-20).
  delete from public.verify_detail_tries v where v.since < p_now - interval '30 days';
  get diagnostics v_vd = row_count;
  return jsonb_build_object('whatsapp_cleared', v_wa, 'activity_removed', v_act,
    'health_checkins_removed', v_hc + v_hl, 'health_leavers', coalesce(array_length(v_gone, 1), 0),
    'link_tries_removed', v_lt, 'verify_tries_removed', v_vt, 'verify_detail_tries_removed', v_vd);
end $$;
revoke all on function public.privacy_retention(timestamptz) from public, anon, authenticated;

-- END OF VERIFY DETAILS ------------------------------------------------------

select public.functions_tidy();
