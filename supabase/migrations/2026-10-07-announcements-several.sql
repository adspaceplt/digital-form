-- ===========================================================================
-- SEVERAL ANNOUNCEMENTS — the team and the clients may each have several
-- announcements live at once, shown one at a time in the one bar, and a
-- stopped one can be deleted. 2026-10-07. Safe to run twice. Rollback at the
-- foot. Mirrored byte for byte in supabase/schema.sql under the same banner;
-- tests/smsql.js compares the two. Runs after ANNOUNCEMENTS and replaces
-- three functions it made.
--
-- WHAT CHANGED (the user, 2026-10-07: "i want multiples for internal and also
-- clients"; "should not stack else it will push down all contents ... 1/2
-- 2/2 or 1/3 2/3 3/3")
--   1. `announcement_now(p_audience)` answers every live announcement for the
--      audience as a list, Important first, then the newest, ten at most
--      (null when none is live). The page shows them one at a time.
--   2. `announcement_save` and `announcement_end` (Restore) no longer stop
--      the others of the audience: posting one adds it.
--   3. `announcement_delete(p_id)`: Team: Announcements deletes a stopped
--      or ended announcement (`live` while it is neither: Stop comes first),
--      filed `team.changed` under subject Announcements. There is no restore.
--
-- ROLLBACK
--   Run the three functions from ANNOUNCEMENTS again (one at a time comes
--   back); leaving `announcement_delete` unused deletes nothing.
-- ===========================================================================

create or replace function public.announcement_now(p_audience text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_list jsonb;
begin
  if p_audience not in ('team', 'clients') then return null; end if;
  if p_audience = 'team' and not public.is_team() then return null; end if;
  select jsonb_agg(public.announcement_json(a) - 'created_by' - 'updated_by' - 'created_at' - 'ended_at'
                   order by (a.tone = 'important') desc, a.updated_at desc)
    into v_list
    from public.announcements a
   where a.id in (select y.id from public.announcements y
                   where y.audience = p_audience and y.ended_at is null
                     and (y.starts_at is null or y.starts_at <= now())
                     and (y.ends_at is null or y.ends_at > now())
                   order by (y.tone = 'important') desc, y.updated_at desc
                   limit 10);
  return v_list;
end $$;
grant execute on function public.announcement_now(text) to anon, authenticated;

create or replace function public.announcement_save(p_id uuid, p_audience text, p_tone text, p_body_en text,
                                                    p_body_zh text, p_link text, p_starts timestamptz,
                                                    p_ends timestamptz)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_en text := btrim(coalesce(p_body_en, ''));
  v_zh text := nullif(btrim(coalesce(p_body_zh, '')), '');
  v_link text := nullif(btrim(coalesce(p_link, '')), '');
  v_tone text := coalesce(nullif(p_tone, ''), 'info');
  a public.announcements;
  v_was text;
begin
  if me.id is null or not public.ops_granted('team.announce', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_audience is null or p_audience not in ('team', 'clients') then return jsonb_build_object('error', 'bad-audience'); end if;
  if v_tone not in ('info', 'important') then return jsonb_build_object('error', 'bad-tone'); end if;
  if char_length(v_en) < 1 or char_length(v_en) > 300 or char_length(coalesce(v_zh, '')) > 300 then
    return jsonb_build_object('error', 'bad-text');
  end if;
  if v_link is not null and v_link !~ '^https://[^\s]+$' then return jsonb_build_object('error', 'bad-link'); end if;
  if p_ends is not null and p_ends <= greatest(coalesce(p_starts, now()), now()) then
    return jsonb_build_object('error', 'bad-window');
  end if;
  if p_id is not null then
    select * into a from public.announcements x where x.id = p_id for update;
    if a.id is null then return jsonb_build_object('error', 'not-found'); end if;
    if a.audience <> p_audience then return jsonb_build_object('error', 'bad-audience'); end if;
    v_was := public.announcement_said(a);
    update public.announcements x
       set tone = v_tone, body_en = v_en, body_zh = v_zh, link = v_link, starts_at = p_starts,
           ends_at = p_ends, ended_at = null, updated_by = me.name, updated_at = now()
     where x.id = p_id returning * into a;
  else
    insert into public.announcements (audience, tone, body_en, body_zh, link, starts_at, ends_at, created_by, updated_by)
    values (p_audience, v_tone, v_en, v_zh, v_link, p_starts, p_ends, me.name, me.name)
    returning * into a;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Announcements',
    case when v_was is null then public.announcement_said(a)
         else v_was || ' → ' || public.announcement_said(a) end);
  return jsonb_build_object('ok', true, 'item', public.announcement_json(a));
end $$;
revoke all on function public.announcement_save(uuid, text, text, text, text, text, timestamptz, timestamptz) from public, anon;
grant execute on function public.announcement_save(uuid, text, text, text, text, text, timestamptz, timestamptz) to authenticated;

create or replace function public.announcement_end(p_id uuid, p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  a public.announcements;
begin
  if me.id is null or not public.ops_granted('team.announce', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into a from public.announcements x where x.id = p_id for update;
  if a.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if coalesce(p_on, false) then
    if a.ended_at is null then return jsonb_build_object('ok', true); end if;
    if a.ends_at is not null and a.ends_at <= now() then return jsonb_build_object('error', 'over'); end if;
    update public.announcements x set ended_at = null, updated_by = me.name, updated_at = now()
     where x.id = a.id returning * into a;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.changed', 'Announcements', 'Restored · ' || public.announcement_said(a));
  else
    if a.ended_at is not null then return jsonb_build_object('ok', true); end if;
    update public.announcements x set ended_at = now() where x.id = a.id returning * into a;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.changed', 'Announcements', 'Stopped · ' || public.announcement_said(a));
  end if;
  return jsonb_build_object('ok', true, 'item', public.announcement_json(a));
end $$;
revoke all on function public.announcement_end(uuid, boolean) from public, anon;
grant execute on function public.announcement_end(uuid, boolean) to authenticated;

create or replace function public.announcement_delete(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  a public.announcements;
begin
  if me.id is null or not public.ops_granted('team.announce', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into a from public.announcements x where x.id = p_id for update;
  if a.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if a.ended_at is null and (a.ends_at is null or a.ends_at > now()) then
    return jsonb_build_object('error', 'live');
  end if;
  delete from public.announcements x where x.id = a.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Announcements', 'Deleted · ' || public.announcement_said(a));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.announcement_delete(uuid) from public, anon;
grant execute on function public.announcement_delete(uuid) to authenticated;

-- END OF SEVERAL ANNOUNCEMENTS ------------------------------------------------

select public.functions_tidy();
