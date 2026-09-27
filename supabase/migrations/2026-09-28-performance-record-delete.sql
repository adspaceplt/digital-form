-- ===========================================================================
-- A PERFORMANCE RECORD CAN BE DELETED — by an admin, with the master code
-- unlocked, the member's name and month typed back and a reason.
-- 2026-09-28. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/perf.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-09-27: "the team performance is missing the
-- delete records for admins"; then chose "any state, with safeguards"):
--  1. `perf_delete` removes one member's month, whatever its state, for an
--     admin alone (`perf_is_admin`, on top of `team.performance` at Manage
--     and a live unlock), never on the admin's own review. The name and the
--     month are typed back (`{name} {Month YYYY}`, case and spaces ignored)
--     and a reason is required. The review, its disputes and its scores go.
--  2. What happened to it is kept. The review's history rows stay (their
--     link to the review is let go rather than deleted with it; the
--     append-only guard now lets that one database write through), and one row
--     more says who deleted which month, when and why, with no score in it.
--     The Activity record's Performance tab reads it as Record deleted.
--  3. A printed record is a document somebody may still hold, so it never
--     becomes "not found": `perf_deleted` keeps its reference, and
--     `/verify/` answers it as an HR Letter, Void. A new review of the same
--     month, once printed, is answered first, as Valid.
--
-- ROLLBACK
--   drop function if exists public.perf_delete(text, uuid, text, text);
--   Re-run perf_events_frozen from THE PERFORMANCE SYSTEM.
--   drop table if exists public.perf_deleted;
--   Re-run verify_serial and perf_activity from PERFORMANCE RECORDS, THEIR
--   TRAIL AND THEIR CHECK.
--   alter table public.perf_events drop constraint if exists perf_events_review_id_fkey,
--     add constraint perf_events_review_id_fkey foreign key (review_id)
--     references public.perf_reviews(id) on delete cascade;
-- ===========================================================================

/* The history outlives the review: deleting a review lets go of its rows'
   link instead of deleting them. The history stays append-only to every
   write a function makes; only the database's own work below another write
   passes (depth > 1), and there an update keeps its new value. Returning the
   old row, as before, quietly cancelled the database's set-null and left the
   row pointing at a review that no longer exists. */
create or replace function public.perf_events_frozen()
returns trigger language plpgsql as $$
begin
  if pg_trigger_depth() > 1 then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  raise exception 'perf-events-append-only';
end $$;
revoke all on function public.perf_events_frozen() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_constraint
              where conname = 'perf_events_review_id_fkey' and confdeltype = 'c') then
    alter table public.perf_events drop constraint perf_events_review_id_fkey;
    alter table public.perf_events add constraint perf_events_review_id_fkey
      foreign key (review_id) references public.perf_reviews(id) on delete set null;
  end if;
end $$;

/* One row per deleted month: enough to answer a printed reference honestly
   and to say who removed it. No score, no grade, no note. */
create table if not exists public.perf_deleted (
  id             uuid primary key default gen_random_uuid(),
  team_member_id uuid references public.team_members(id) on delete cascade,
  period         date not null,
  serial         text,
  status         text not null,
  printed        boolean not null default false,
  released_at    timestamptz,
  deleted_at     timestamptz not null default now(),
  deleted_by     uuid references public.team_members(id) on delete set null,
  reason         text not null
);
create index if not exists perf_deleted_serial_idx on public.perf_deleted(upper(serial)) where serial is not null;
alter table public.perf_deleted enable row level security;
revoke all on public.perf_deleted from public, anon, authenticated;

create or replace function public.perf_delete(p_token text, p_review uuid, p_confirm text, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_err     text;
  v_me      public.team_members;
  v_rev     public.perf_reviews;
  v_name    text;
  v_month   text;
  v_printed boolean;
begin
  v_err := public.perf_check(p_token, 'manage');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  if not public.perf_is_admin() then return jsonb_build_object('error', 'admin-only'); end if;
  v_me := public.ops_me();
  select * into v_rev from public.perf_reviews pr where pr.id = p_review for update;
  if v_rev.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_rev.team_member_id = v_me.id then return jsonb_build_object('error', 'own-review'); end if;
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-needed'); end if;
  select tm.name into v_name from public.team_members tm where tm.id = v_rev.team_member_id;
  v_month := public.perf_month_word(v_rev.period);
  if lower(regexp_replace(btrim(coalesce(p_confirm, '')), '\s+', ' ', 'g'))
     <> lower(regexp_replace(btrim(coalesce(v_name, '') || ' ' || v_month), '\s+', ' ', 'g')) then
    return jsonb_build_object('error', 'confirm-mismatch');
  end if;
  v_printed := exists (select 1 from public.perf_events pe where pe.review_id = v_rev.id and pe.kind = 'printed');

  insert into public.perf_deleted (team_member_id, period, serial, status, printed, released_at, deleted_by, reason)
  values (v_rev.team_member_id, v_rev.period, v_rev.serial, v_rev.status, v_printed, v_rev.released_at,
          v_me.id, btrim(p_reason));
  perform public.perf_log(null, v_rev.team_member_id, 'deleted',
    jsonb_build_object('period', v_rev.period, 'month', v_month, 'serial', v_rev.serial,
                       'status', v_rev.status, 'printed', v_printed, 'reason', btrim(p_reason)));
  delete from public.perf_reviews pr where pr.id = v_rev.id;
  return jsonb_build_object('ok', true, 'month', v_month, 'status', v_rev.status, 'printed', v_printed);
end $$;
revoke all on function public.perf_delete(text, uuid, text, text) from public, anon;
grant execute on function public.perf_delete(text, uuid, text, text) to authenticated;

/* The Activity record's Performance tab: the steps it lists, and now a
   deleted month, whose period comes from the row itself. */
create or replace function public.perf_activity(p_limit integer default 200)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare me_row public.team_members;
begin
  me_row := public.ops_me();
  if me_row.id is null or not public.ops_granted('team.performance', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(jsonb_build_object(
             'at', e.created_at, 'kind', e.kind, 'member', tm.name,
             'period', coalesce(rv.period, case when e.kind = 'deleted' then (e.detail ->> 'period')::date end),
             'actor', e.actor_email, 'actor_name', ac.name) order by e.created_at desc)
      from (select pe.* from public.perf_events pe
             where pe.kind in ('released', 'disputed', 'decided', 'acknowledged',
                               'finalised', 'reopened', 'returned', 'printed', 'deleted')
               and pe.team_member_id is distinct from me_row.id
             order by pe.created_at desc
             limit greatest(1, least(coalesce(p_limit, 200), 500))) e
      left join public.team_members tm on tm.id = e.team_member_id
      left join public.perf_reviews rv on rv.id = e.review_id
      left join public.team_members ac on ac.id = e.actor_id), '[]'::jsonb));
end $$;
revoke all on function public.perf_activity(integer) from public, anon, authenticated;
grant execute on function public.perf_activity(integer) to authenticated;

/* The verify page, with a deleted printed record answered as Void. A
   standing record under the same reference is answered first. */
create or replace function public.verify_serial(p_serial text)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  s text := upper(btrim(coalesce(p_serial, '')));
  sd text;
  d public.documents%rowtype;
  l public.client_documents%rowtype;
  rv public.perf_reviews%rowtype;
  dl public.perf_deleted%rowtype;
begin
  if length(s) < 3 or length(s) > 40 then return jsonb_build_object('found', false); end if;
  sd := replace(s, '/', '-');
  select * into d from public.documents
   where upper(serial) = s or replace(upper(serial), '/', '-') = sd
   order by (upper(serial) = s) desc, (voided_at is null) desc, created_at desc limit 1;
  if d.id is not null then
    return jsonb_build_object('found', true, 'serial', d.serial,
      'kind', case when d.family = 'hr' then 'HR Letter' else d.kind end,
      'issued_at', d.issued_at,
      'state', case when d.voided_at is null then 'valid' else 'voided' end);
  end if;
  select * into l from public.client_documents
   where upper(number) = s or replace(upper(number), '/', '-') = sd
   order by (upper(number) = s) desc limit 1;
  if l.id is not null then
    return jsonb_build_object('found', true, 'serial', l.number, 'kind', 'Letter of Offer',
      'issued_at', l.issued_at,
      'state', case when l.voided_at is not null then 'voided'
                    when l.superseded_by is not null then 'replaced'
                    else 'valid' end);
  end if;
  select * into rv from public.perf_reviews pr
   where (upper(pr.serial) = s or replace(upper(pr.serial), '/', '-') = sd)
     and exists (select 1 from public.perf_events pe where pe.review_id = pr.id and pe.kind = 'printed')
   limit 1;
  if rv.id is not null then
    return jsonb_build_object('found', true, 'serial', rv.serial, 'kind', 'HR Letter',
      'issued_at', rv.released_at,
      'state', case when rv.status = 'draft' then 'replaced' else 'valid' end);
  end if;
  select * into dl from public.perf_deleted pd
   where pd.printed and (upper(pd.serial) = s or replace(upper(pd.serial), '/', '-') = sd)
   order by pd.deleted_at desc limit 1;
  if dl.id is not null then
    return jsonb_build_object('found', true, 'serial', dl.serial, 'kind', 'HR Letter',
      'issued_at', dl.released_at, 'state', 'voided');
  end if;
  return jsonb_build_object('found', false);
end $$;
revoke all on function public.verify_serial(text) from public;
grant execute on function public.verify_serial(text) to anon, authenticated;

-- END OF A PERFORMANCE RECORD CAN BE DELETED ---------------------------------
