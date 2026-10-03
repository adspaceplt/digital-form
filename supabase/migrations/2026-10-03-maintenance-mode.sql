-- ===========================================================================
-- UPGRADE MODE — an admin covers the portal's pages while it is upgraded.
-- 2026-10-03. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the
-- two.
--
-- WHAT CHANGED
--   The user, 2026-10-03: an admin-only switch that shows every portal page,
--   internal and client facing, one cover reading Upgrading in progress,
--   now or from a set date and time, until it is switched off or an end set
--   with it passes. One row in `app_flags` holds it (RLS on, no policy, no
--   grant): `maintenance_state()` answers anybody whether it is on now
--   (`on`), switched on at all (`set`), its note and its window; and
--   `maintenance_set()` changes it for an admin alone, filed as Access
--   changed under Team (`team.changed`, subject Portal, "Upgrade mode: off →
--   on"). The page draws the cover (`js/maintenance.js`) and an admin keeps
--   working under a banner; the front door and short links stay up. Pages
--   only: the database keeps answering while it is on.
--
-- ROLLBACK
--   Remove the functions maintenance_set(boolean, text, timestamptz,
--   timestamptz) and maintenance_state(), then the table app_flags.
-- ===========================================================================

create table if not exists public.app_flags (
  key        text primary key,
  on_now     boolean not null default false,
  note       text,
  starts_at  timestamptz,
  ends_at    timestamptz,
  set_by     text,
  set_at     timestamptz
);
alter table public.app_flags add column if not exists starts_at timestamptz;
alter table public.app_flags add column if not exists ends_at timestamptz;
alter table public.app_flags enable row level security;
revoke all on table public.app_flags from public, anon, authenticated;

create or replace function public.maintenance_state()
returns jsonb language sql security definer stable set search_path = public as $$
  select coalesce((select jsonb_build_object(
                     'on', f.on_now and (f.starts_at is null or f.starts_at <= now())
                                    and (f.ends_at is null or f.ends_at > now()),
                     'set', f.on_now and (f.ends_at is null or f.ends_at > now()),
                     'note', f.note,
                     'since', coalesce(f.starts_at, f.set_at),
                     'starts_at', f.starts_at,
                     'ends_at', f.ends_at)
                     from public.app_flags f where f.key = 'maintenance'),
                  jsonb_build_object('on', false, 'set', false))
$$;
revoke all on function public.maintenance_state() from public;
grant execute on function public.maintenance_state() to anon, authenticated;

create or replace function public.maintenance_set(p_on boolean, p_note text default null,
                                                  p_starts timestamptz default null,
                                                  p_ends timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_was boolean;
  v_who text;
  v_on boolean := coalesce(p_on, false);
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_when text := '';
begin
  if not public.allowed('admin') then
    return jsonb_build_object('error', 'denied');
  end if;
  if v_on and p_ends is not null and p_ends <= greatest(coalesce(p_starts, now()), now()) then
    return jsonb_build_object('error', 'bad-window');
  end if;
  select coalesce(t.name, t.email) into v_who from public.team_members t
   where lower(t.email) = lower(auth.jwt() ->> 'email') and t.active limit 1;
  select f.on_now and (f.ends_at is null or f.ends_at > now()) into v_was
    from public.app_flags f where f.key = 'maintenance';
  insert into public.app_flags (key, on_now, note, starts_at, ends_at, set_by, set_at)
  values ('maintenance', v_on, case when v_on then left(v_note, 300) end,
          case when v_on and p_starts > now() then p_starts end,
          case when v_on then p_ends end, v_who, now())
  on conflict (key) do update
    set on_now = excluded.on_now, note = excluded.note, starts_at = excluded.starts_at,
        ends_at = excluded.ends_at, set_by = excluded.set_by, set_at = excluded.set_at;
  if v_on and p_starts > now() then
    v_when := ' · from ' || regexp_replace(to_char(p_starts at time zone 'Asia/Kuala_Lumpur', 'FMDD Mon YYYY HH24:MI'), '\mSep\M', 'Sept');
  end if;
  if v_on and p_ends is not null then
    v_when := v_when || ' · until ' || regexp_replace(to_char(p_ends at time zone 'Asia/Kuala_Lumpur', 'FMDD Mon YYYY HH24:MI'), '\mSep\M', 'Sept');
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_who, 'admin'), 'team.changed', 'Portal',
          'Upgrade mode: ' || case when coalesce(v_was, false) then 'on' else 'off' end || ' → ' ||
          case when v_on then 'on' else 'off' end || v_when ||
          case when v_on then coalesce(' · ' || left(v_note, 300), '') else '' end);
  return public.maintenance_state();
end $$;
revoke all on function public.maintenance_set(boolean, text, timestamptz, timestamptz) from public, anon;
grant execute on function public.maintenance_set(boolean, text, timestamptz, timestamptz) to authenticated;

-- END OF UPGRADE MODE --------------------------------------------------------
