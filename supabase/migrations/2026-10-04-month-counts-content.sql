-- ===========================================================================
-- MONTH COUNTS LEAVE REPORTS OUT — the count of what a month holds against
-- its plan leaves out the report tasks the month makes for itself.
-- 2026-10-04. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the
-- two. Runs after MONTH REPORTS.
--
-- WHAT CHANGED
--   `ops_engagement_counts` adds `content`: the month's live tasks less its
--   report tasks (`report_social`, `report_ads`), as the report's month gate
--   counts them. The New sheet reads it as "n added" against the pieces
--   planned. `live`, `open` and `done` still count every task, so a month
--   stays in production until its report is done.
--
-- ROLLBACK
--   Run the MONTH STAGES FOLLOW THE WORK section's ops_engagement_counts
--   again.
-- ===========================================================================

/* A month's tasks, counted over the whole month whoever asks: live (not
   cancelled), open (not finished), done (completed), and content (live, less
   the report tasks the month makes for itself). Only months the caller may
   see answer. */
create or replace function public.ops_engagement_counts(p_engagements uuid[])
returns jsonb
language sql security definer stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'engagement_id', e.id,
           'live', (select count(*) from public.ops_tasks t
                     where t.engagement_id = e.id and t.archived_at is null
                       and t.cancelled_at is null),
           'open', (select count(*) from public.ops_tasks t
                     where t.engagement_id = e.id and t.archived_at is null
                       and t.cancelled_at is null and t.completed_at is null),
           'done', (select count(*) from public.ops_tasks t
                     where t.engagement_id = e.id and t.archived_at is null
                       and t.cancelled_at is null and t.completed_at is not null),
           'content', (select count(*) from public.ops_tasks t
                        where t.engagement_id = e.id and t.archived_at is null
                          and t.cancelled_at is null
                          and coalesce(t.source_type, '') not in ('report_social', 'report_ads')))), '[]'::jsonb)
    from public.ops_engagements e
   where e.id = any (coalesce(p_engagements, '{}'::uuid[]))
     and public.ops_may_see_engagement(e.id)
$$;
revoke all on function public.ops_engagement_counts(uuid[]) from public, anon;
grant execute on function public.ops_engagement_counts(uuid[]) to authenticated;

-- END OF MONTH COUNTS LEAVE REPORTS OUT ----------------------------------------
