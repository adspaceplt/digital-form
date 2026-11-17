-- ============================================================================
-- THE LATEST BUILD REQUIRED (2026-11-17)
-- ============================================================================
-- The user, 2026-11-17 ("ok build it"): everyone ends up on the same merged
-- build. Every open console asks /version.json once a minute (Pages, not
-- the database) and offers Refresh on a newer build; an admin may also
-- require the live build, and a console below it refreshes itself as soon
-- as nothing is open in it.
--
--   * `app_flags` row `build:min` holds the build required: its commit in
--     `note`, its build time in `starts_at`. RLS on, no policy, no grant, as
--     every row of the table.
--   * `build_min()` (internal) answers `{commit, built}` or null.
--   * `build_state()` (the team) answers the build required, for Settings.
--   * `build_require(p_commit, p_built)` (`team.upgrade` at Work): stores
--     the build the page read from /version.json as the minimum, or clears
--     it with a null commit (Undo); `bad-build` for a commit that is not
--     7 to 40 hex characters or a time before 14 Aug 2023 or ahead of now.
--     Filed `team.changed` under Portal, from and to.
--   * `page_pulse` answers `build` to the console (audience team), every
--     part it answered before kept.
--
-- ORDER: this file (connector), then the pages. A page served before never
-- asks for `build` and reads the rest as before. Safe to run twice.
-- ROLLBACK: run 2026-10-24-colleague-last-seen.sql's page_pulse again (the
-- last before this one, mirrored in schema.sql's PAGE AVAILABILITY band);
-- the three functions and the `build:min` row may stay.
-- ============================================================================

-- THE LATEST BUILD REQUIRED --------------------------------------------------

create or replace function public.build_min()
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('commit', f.note, 'built', f.starts_at, 'set_by', f.set_by, 'set_at', f.set_at)
    from public.app_flags f
   where f.key = 'build:min' and f.on_now and f.note is not null and f.starts_at is not null
$$;
revoke all on function public.build_min() from public, anon, authenticated;

create or replace function public.build_word(p_commit text, p_built timestamptz)
returns text
language sql immutable set search_path = public as $$
  select case when p_commit is null or p_built is null then 'not set'
    else 'v' || to_char(p_built at time zone 'Asia/Kuala_Lumpur', 'YY.MM.DD') || ' · ' || left(p_commit, 7) end
$$;
revoke all on function public.build_word(text, timestamptz) from public, anon, authenticated;

create or replace function public.build_state()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_team() then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('min', public.build_min());
end $$;
revoke all on function public.build_state() from public, anon;
grant execute on function public.build_state() to authenticated;

create or replace function public.build_require(p_commit text, p_built timestamptz)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_who text;
  v_was jsonb;
  v_commit text := lower(nullif(btrim(coalesce(p_commit, '')), ''));
begin
  if not public.ops_granted('team.upgrade', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if v_commit is not null and (v_commit !~ '^[0-9a-f]{7,40}$' or p_built is null
      or p_built < timestamptz '2023-08-14 00:00+08' or p_built > now() + interval '10 minutes') then
    return jsonb_build_object('error', 'bad-build');
  end if;
  select coalesce(t.name, t.email) into v_who from public.team_members t
   where lower(t.email) = lower(auth.jwt() ->> 'email') and t.active limit 1;
  v_was := public.build_min();
  insert into public.app_flags (key, on_now, note, starts_at, set_by, set_at)
  values ('build:min', v_commit is not null, v_commit, case when v_commit is not null then p_built end, v_who, now())
  on conflict (key) do update
    set on_now = excluded.on_now, note = excluded.note, starts_at = excluded.starts_at,
        set_by = excluded.set_by, set_at = excluded.set_at;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_who, 'admin'), 'team.changed', 'Portal',
          'Latest build required: ' || public.build_word(v_was ->> 'commit', (v_was ->> 'built')::timestamptz)
          || ' → ' || public.build_word(v_commit, case when v_commit is not null then p_built end));
  return jsonb_build_object('ok', true, 'min', public.build_min(), 'was', v_was);
end $$;
revoke all on function public.build_require(text, timestamptz) from public, anon;
grant execute on function public.build_require(text, timestamptz) to authenticated;

create or replace function public.page_pulse(p_audience text default null, p_bell boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members;
  v  jsonb := jsonb_build_object('maintenance', public.maintenance_state(), 'pages', public.page_states());
begin
  if p_audience in ('team', 'clients') then
    v := v || jsonb_build_object('announcements', coalesce(public.announcement_now(p_audience), '[]'::jsonb));
  end if;
  /* The console's minute says the colleague is active, at most once every
     15 minutes; a client page asks for the clients and never stamps. It
     also reads the build required (2026-11-17). */
  if p_audience = 'team' then
    begin
      update public.team_members t set last_seen_at = now()
       where t.id = (public.ops_me()).id
         and (t.last_seen_at is null or t.last_seen_at < now() - interval '15 minutes');
    exception when others then null;
    end;
    v := v || jsonb_build_object('build', public.build_min());
  end if;
  if coalesce(p_bell, false) then
    me := public.ops_me();
    if me.id is not null then
      v := v || jsonb_build_object('bell', jsonb_build_object(
        'unread', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc)
                              from (select * from public.ops_notifications o
                                     where o.team_member_id = me.id and o.read_at is null and o.hidden_at is null
                                     order by o.created_at desc limit 30) x), '[]'::jsonb),
        'earlier', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc)
                               from (select * from public.ops_notifications o
                                      where o.team_member_id = me.id and o.read_at is not null and o.hidden_at is null
                                        and o.created_at >= now() - interval '7 days'
                                      order by o.created_at desc limit 10) x), '[]'::jsonb)));
    end if;
  end if;
  return v;
end $$;
revoke all on function public.page_pulse(text, boolean) from public;
grant execute on function public.page_pulse(text, boolean) to anon, authenticated;

-- END OF THE LATEST BUILD REQUIRED -------------------------------------------

select public.functions_tidy();
