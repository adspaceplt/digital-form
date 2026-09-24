-- ===========================================================================
-- READINESS IS THE FIRST MONTH'S — onboarding is done once a client, not
-- every month.
-- 2026-09-24. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the two.
--
-- WHAT THIS CHANGES, AND WHAT IT LEAVES ALONE.
--
--   The Onboarding and Pre-advertising checklists are what happens when a
--   client starts, so they belong to the client's first month and to no
--   later one (the user, 2026-09-24: "the readiness is only when its the
--   first engagement with clients, not every single month"). A later month
--   carries no checks at all, so its gate to Ready is the content meeting
--   alone: `ops_engagement_set_status` already refuses only while a check
--   row is open, and a month with none has none open. Nothing about the gate
--   itself is rewritten.
--
--   1. Existing months: each client's first month (the earliest period)
--      takes the furthest state either check reached on any of the client's
--      months, with who ticked it and when, so a tick somebody made on the
--      second month is not lost; then the rows on every later month go.
--   2. `ops_engagement_upsert` seeds the two checks only when the client has
--      no other month.
--   3. Deleting a client's first month hands its checks to the earliest month
--      left, by trigger, so onboarding that was ticked is not deleted with a
--      month keyed in by mistake.
--
-- ROLLBACK
--   drop trigger if exists ops_engagements_hand_on_checks on public.ops_engagements;
--   drop function if exists public.ops_engagements_hand_on_checks();
--   Re-run 2026-09-24-the-month-in-two-ticks.sql for the upsert that seeds
--   every month. The rows removed from later months are not put back.
-- ===========================================================================

-- 1. The first month keeps what any month recorded --------------------------------
insert into public.ops_engagement_checks (engagement_id, key)
select f.id, k.key
  from (select distinct on (client_id) id, client_id from public.ops_engagements
         order by client_id, period, created_at) f
 cross join (values ('onboarding'), ('pre_ads')) k(key)
 where exists (select 1 from public.ops_engagement_checks c
                 join public.ops_engagements e on e.id = c.engagement_id
                where e.client_id = f.client_id)
on conflict do nothing;

with firsts as (
  select distinct on (client_id) id, client_id from public.ops_engagements
   order by client_id, period, created_at
), best as (
  select distinct on (e.client_id, c.key)
         e.client_id, c.key, c.state, c.owner_id, c.updated_by, c.updated_at, c.note
    from public.ops_engagement_checks c
    join public.ops_engagements e on e.id = c.engagement_id
   order by e.client_id, c.key,
            case c.state when 'ready' then 0 when 'na' then 1 when 'in_progress' then 2
                         when 'waiting_client' then 3 else 4 end,
            c.updated_at desc nulls last
)
update public.ops_engagement_checks c
   set state = b.state, owner_id = b.owner_id, updated_by = b.updated_by,
       updated_at = b.updated_at, note = b.note
  from firsts f join best b on b.client_id = f.client_id
 where c.engagement_id = f.id and c.key = b.key and c.state is distinct from b.state;

delete from public.ops_engagement_checks c
 using public.ops_engagements e
 where e.id = c.engagement_id
   and e.id <> (select f.id from public.ops_engagements f where f.client_id = e.client_id
                 order by f.period, f.created_at limit 1);

-- 2. A new month is seeded only when it is the client's first ----------------------
/* One a client a month. A second call for the same month edits the one row
   rather than making a second. The two checks are onboarding, so they are
   seeded on the client's first month and on no later one. */
create or replace function public.ops_engagement_upsert(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  cid uuid;
  per text;
  eid uuid;
  k text;
  fresh boolean := false;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  cid := (p_payload ->> 'client_id')::uuid;
  per := p_payload ->> 'period';
  if cid is null or not exists (select 1 from public.clients where id = cid) then
    return jsonb_build_object('error', 'client-required');
  end if;
  if per is null or per !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;

  select e.id into eid from public.ops_engagements e where e.client_id = cid and e.period = per;
  if eid is null then
    insert into public.ops_engagements (client_id, period, manager_id, planned_count, drive_url, created_by)
    values (cid, per, coalesce((p_payload ->> 'manager_id')::uuid, m.id),
            coalesce((p_payload ->> 'planned_count')::integer, 0),
            nullif(p_payload ->> 'drive_url', ''), m.id)
    on conflict (client_id, period) do nothing
    returning id into eid;
    /* Somebody else made it between the read and the write: theirs stands. */
    if eid is null then
      select e.id into eid from public.ops_engagements e where e.client_id = cid and e.period = per;
    else
      fresh := true;
    end if;
  end if;
  if fresh then
    if not exists (select 1 from public.ops_engagements o where o.client_id = cid and o.id <> eid) then
    foreach k in array array['onboarding', 'pre_ads'] loop
      insert into public.ops_engagement_checks (engagement_id, key) values (eid, k)
      on conflict do nothing;
    end loop;
    end if;
    perform public.ops_engagement_log(eid, 'created', p_payload - 'client_id');
  else
    if not public.ops_may_see_engagement(eid) then return jsonb_build_object('error', 'denied'); end if;
    /* Asked for with nothing to change, the month is answered as it stands:
       a task made for a month joins it without editing it. */
    if (p_payload - 'client_id' - 'period') = '{}'::jsonb then
      return public.ops_engagement_json(eid) || jsonb_build_object('created', false);
    end if;
    update public.ops_engagements set
      manager_id = coalesce((p_payload ->> 'manager_id')::uuid, manager_id),
      planned_count = coalesce((p_payload ->> 'planned_count')::integer, planned_count),
      drive_url = case when p_payload ? 'drive_url' then nullif(p_payload ->> 'drive_url', '') else drive_url end,
      updated_at = now(), version = version + 1
    where id = eid;
    perform public.ops_engagement_log(eid, 'edited', p_payload - 'client_id' - 'period');
  end if;
  return public.ops_engagement_json(eid) || jsonb_build_object('created', fresh);
end $$;
grant execute on function public.ops_engagement_upsert(jsonb) to authenticated;

-- 3. The first month's checks outlive the month --------------------------------------
/* A first month deleted as a mistake takes the onboarding record to the
   earliest month left rather than with it. Where that month already holds
   checks, they stand. */
create or replace function public.ops_engagements_hand_on_checks()
returns trigger
language plpgsql security definer set search_path = public as $$
declare nxt uuid;
begin
  select e.id into nxt from public.ops_engagements e
   where e.client_id = old.client_id and e.id <> old.id
   order by e.period, e.created_at limit 1;
  if nxt is not null and not exists (select 1 from public.ops_engagement_checks where engagement_id = nxt) then
    update public.ops_engagement_checks set engagement_id = nxt where engagement_id = old.id;
  end if;
  return old;
end $$;
drop trigger if exists ops_engagements_hand_on_checks on public.ops_engagements;
create trigger ops_engagements_hand_on_checks before delete on public.ops_engagements
  for each row execute function public.ops_engagements_hand_on_checks();

-- END OF READINESS IS THE FIRST MONTH'S -------------------------------------
