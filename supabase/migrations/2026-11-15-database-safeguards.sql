-- ===========================================================================
-- DATABASE SAFEGUARDS (2026-11-15)
-- ===========================================================================
-- WHY: the phase 2 audit (2026-11-15; the user: "Ok fix all 21"), findings
-- 19 to 21.
--
-- WHAT IT CHANGES
--   * Every table and view in public keeps nothing for anon: 46 tables still
--     held Supabase's default grants to anon (TRUNCATE included). Row level
--     security already admitted no anon read; this is the second wall. No
--     page signed out reads a table (each asks a function), so nothing it
--     does changes. Run on every pass, so a table made later is caught at the
--     next run; Supabase's default privileges are left as they stand.
--   * `client_touch_meet_prepare(uuid)` and `client_touch_set_meet(uuid,
--     text, text)` (invoker, outside open_to_anon) are no longer anon's.
--   * Six indexes on hot foreign keys: campaign_options(creator_id),
--     ops_notifications(task_id), creator_bills(option_id),
--     ops_tasks(campaign_id), ops_tasks(batch_id), ops_tasks(template_id).
--
-- ORDER: this file alone; no page changes. Safe to run twice.
--
-- ROLLBACK: grant back what the pages never needed only if a signed-out read
-- is found to rely on it (`grant select on public.<table> to anon`); the
-- functions: `grant execute on function public.client_touch_meet_prepare(uuid),
-- public.client_touch_set_meet(uuid, text, text) to anon`; the indexes:
-- drop index if exists public.campaign_options_creator_idx,
-- public.ops_notifications_task_idx, public.creator_bills_option_idx,
-- public.ops_tasks_campaign_idx, public.ops_tasks_batch_idx,
-- public.ops_tasks_template_idx;
-- ===========================================================================

-- DATABASE SAFEGUARDS ---------------------------------------------------------

/* No page signed out reads a table: every public page asks a function. A
   table keeps nothing for anon, Supabase's default grants included, on every
   run (views as tables). */
do $$
declare t record;
begin
  for t in select c.relname from pg_class c
            where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p', 'v', 'm', 'f')
  loop
    execute format('revoke all on public.%I from anon', t.relname);
  end loop;
end $$;

/* Two invoker functions of a client's Calls and visits meeting are the
   team's alone (meet-create asks them as the caller). */
revoke execute on function public.client_touch_meet_prepare(uuid) from public, anon;
revoke execute on function public.client_touch_set_meet(uuid, text, text) from public, anon;
grant execute on function public.client_touch_meet_prepare(uuid) to authenticated;
grant execute on function public.client_touch_set_meet(uuid, text, text) to authenticated;

/* Indexes on the foreign keys the pages and the deletes read most. */
create index if not exists campaign_options_creator_idx on public.campaign_options (creator_id);
create index if not exists ops_notifications_task_idx on public.ops_notifications (task_id) where task_id is not null;
create index if not exists creator_bills_option_idx on public.creator_bills (option_id) where option_id is not null;
create index if not exists ops_tasks_campaign_idx on public.ops_tasks (campaign_id) where campaign_id is not null;
create index if not exists ops_tasks_batch_idx on public.ops_tasks (batch_id) where batch_id is not null;
create index if not exists ops_tasks_template_idx on public.ops_tasks (template_id) where template_id is not null;

-- END OF DATABASE SAFEGUARDS --------------------------------------------------

select public.functions_tidy();
