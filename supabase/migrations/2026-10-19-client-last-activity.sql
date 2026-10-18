-- ===========================================================================
-- CLIENT LAST ACTIVITY — the Clients list's Last activity in one read.
-- 2026-10-19. Safe to run twice. Rollback at the foot. Mirrored byte for
-- byte in supabase/schema.sql under the same banner; tests/sql.js compares
-- the two.
--
-- WHAT CHANGED (the third audit, item 7)
--   The Clients list worked out each client's Last activity from three
--   reads of every row (calls and visits, Letters of Offer, Documents),
--   none paged, so past PostgREST's thousand rows a table the newest facts
--   were cut off and a client read as quiet that was not. One function now
--   answers, for each client, the newest fact of each kind: the newest call
--   or visit not removed (its kind), the newest Letter of Offer and the
--   newest document (its kind), none dated ahead of now. It runs as the
--   caller (security invoker), so each table's own read policies and the
--   client scope decide what a colleague is answered, as the three reads
--   did; the page takes the newest of the three and names it as before.
--   A call's day is a date; it is answered as that day's midnight in UTC,
--   the moment the page read it as.
--
-- ROLLBACK
--   drop function if exists public.client_last_activity();
--   (pages served before this read the three tables themselves)
-- ===========================================================================

create or replace function public.client_last_activity()
returns table (client_id uuid, source text, kind text, at timestamptz)
language sql stable security invoker set search_path = public as $$
  select t.client_id, 'touch'::text, t.kind::text, t.at
    from (select distinct on (x.client_id) x.client_id, x.kind, (x.happened_at::timestamp at time zone 'UTC') as at
            from public.client_touches x
           where x.archived_at is null and x.client_id is not null
             and (x.happened_at::timestamp at time zone 'UTC') <= now() + interval '1 minute'
           order by x.client_id, x.happened_at desc) t
  union all
  select d.client_id, 'letter'::text, null::text, max(d.created_at)
    from public.client_documents d
   where d.client_id is not null and d.created_at <= now() + interval '1 minute'
   group by d.client_id
  union all
  select g.client_id, 'document'::text, g.kind::text, g.created_at
    from (select distinct on (y.client_id) y.client_id, y.kind, y.created_at
            from public.documents y
           where y.client_id is not null and y.created_at <= now() + interval '1 minute'
           order by y.client_id, y.created_at desc) g
$$;

revoke all on function public.client_last_activity() from public, anon;
grant execute on function public.client_last_activity() to authenticated;

-- END OF CLIENT LAST ACTIVITY ------------------------------------------------

select public.functions_tidy();
