-- ===========================================================================
-- SIGN-IN SESSIONS (2026-11-20)
-- ===========================================================================
-- WHY (the user, 2026-11-20: "log every users active sessions as a code
-- … so we know which user session is that", then "A ok admins": read what
-- Supabase already keeps, no new writes or rows)
--   An admin could see when a colleague was last active, never on which
--   device, nor end one device's sign-in.
--
-- WHAT IT ADDS
--   * `team.sessions`, a granted part (an admin's by itself, Manage alone
--     offered, `access_keys`), as every admin-only act is.
--   * `session_device(p_agent)`: a browser's description in words
--     (iPhone · Safari), the one reading of it; internal.
--   * `team_member_sessions(p_id)` (`team.sessions`): a colleague's live
--     Supabase sessions (`auth.sessions`, not expired), newest active first:
--     the session id, the device, signed in, last active (the session's
--     last renewal, about hourly while open) and whether it is the caller's
--     own. Nothing is written; no IP address is answered.
--   * `team_session_end(p_id, p_session)` (`team.sessions`): ends one of a
--     colleague's sessions (its renewal is refused, so the device signs out
--     within the hour its access lasts), filed `team.changed` under Sign-in
--     sessions. Refuses `denied`, `not-found`, `own-session` (Sign out ends
--     one's own) and `system-account` (only that account ends its own).
--
-- ORDER: this file (the API, as a whole: it holds a delete), then the
-- pages. A page from before never asks; one after this file reads the list.
-- Safe to run twice. Rollback: drop the three functions and delete the
-- access key row; nothing else changed.
-- ===========================================================================

insert into public.access_keys (key, tier, label) values ('team.sessions', 'granted', 'team.sessions')
on conflict (key) do nothing;

create or replace function public.session_device(p_agent text)
returns text language sql immutable set search_path = public as $$
  select (case
            when a ~* 'iphone' then 'iPhone' when a ~* 'ipad' then 'iPad' when a ~* 'android' then 'Android'
            when a ~* 'macintosh|mac os x' then 'Mac' when a ~* 'windows' then 'Windows'
            when a ~* 'cros' then 'Chromebook' when a ~* 'linux' then 'Linux' else 'Unknown device' end)
      || coalesce(' · ' || (case
            when a ~* 'edg(e|a|ios)?/' then 'Edge' when a ~* 'firefox|fxios' then 'Firefox'
            when a ~* 'samsungbrowser' then 'Samsung Internet' when a ~* 'chrome|crios' then 'Chrome'
            when a ~* 'version/.*safari' then 'Safari' else null end), '')
    from (select coalesce(p_agent, '') a) x
$$;
revoke all on function public.session_device(text) from public, anon, authenticated;

create or replace function public.team_member_sessions(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
begin
  if not public.ops_granted('team.sessions', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into m from public.team_members t where t.id = p_id and t.erased_at is null;
  if m.id is null then return jsonb_build_object('error', 'not-found'); end if;
  return jsonb_build_object('sessions', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', x.id, 'device', public.session_device(x.user_agent), 'created_at', x.created_at,
             'last_at', x.last_at, 'mine', x.id::text = coalesce(auth.jwt() ->> 'session_id', ''))
           order by x.last_at desc nulls last)
      from (select s.id, s.user_agent, s.created_at,
                   greatest(s.updated_at, s.refreshed_at at time zone 'UTC', s.created_at) as last_at
              from auth.sessions s
              join auth.users u on u.id = s.user_id
             where lower(u.email) = lower(m.email)
               and (s.not_after is null or s.not_after > now())) x), '[]'::jsonb));
end $$;
revoke all on function public.team_member_sessions(uuid) from public, anon, authenticated;
grant execute on function public.team_member_sessions(uuid) to authenticated;

create or replace function public.team_session_end(p_id uuid, p_session uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  m      public.team_members;
  v_dev  text;
begin
  if me.id is null or not public.ops_granted('team.sessions', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into m from public.team_members t where t.id = p_id and t.erased_at is null;
  if m.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if coalesce(m.system, false) and m.id <> me.id then return jsonb_build_object('error', 'system-account'); end if;
  if p_session::text = coalesce(auth.jwt() ->> 'session_id', '') then return jsonb_build_object('error', 'own-session'); end if;
  select public.session_device(s.user_agent) into v_dev
    from auth.sessions s join auth.users u on u.id = s.user_id
   where s.id = p_session and lower(u.email) = lower(m.email);
  if v_dev is null then return jsonb_build_object('error', 'not-found'); end if;
  delete from auth.sessions s where s.id = p_session;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Sign-in sessions',
          m.name || ': signed out on ' || v_dev || ' (' || left(p_session::text, 6) || ')');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.team_session_end(uuid, uuid) from public, anon, authenticated;
grant execute on function public.team_session_end(uuid, uuid) to authenticated;

-- END OF SIGN-IN SESSIONS ----------------------------------------------------

select public.functions_tidy();
