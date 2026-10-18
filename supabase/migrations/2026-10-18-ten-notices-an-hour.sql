-- ===========================================================================
-- TEN NOTICES AN HOUR — a colleague sends at most ten notices in any hour
-- (2026-10-18)
-- ===========================================================================
-- WHY (Team audit, item 16): `team_notice_send` wrote a bell row and a
-- push for every colleague on each press with no limit, so a stuck key, a
-- page sending twice or a misused part could fill every colleague's bell
-- and phone.
--
-- WHAT IT CHANGES
--   * `team_notice_send` refuses `too-many` (with `limit` 10 and `next`, the
--     moment the next may go) once the sender has sent ten notices in the
--     hour before, counted from `team_notices` under a lock held for the
--     sender to the end of the transaction, so two presses at once are
--     counted one after the other. Ten is a safety limit, not a business
--     figure, so it is held in the function as an invitation's count is.
--     Every refusal before it stands as it was.
--
-- ORDER: the page (it words `too-many`), then this file. Safe to run twice.
-- Rollback: TEAM NOTICES' `team_notice_send`.
-- ===========================================================================

create or replace function public.team_notice_send(p_title text, p_body text, p_to uuid[])
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_title text := btrim(coalesce(p_title, ''));
  v_body  text := nullif(btrim(coalesce(p_body, '')), '');
  v_to    uuid[];
  v_id    uuid;
  n       int;
  v_sent  int;
  v_first timestamptz;
begin
  if me.id is null or not public.ops_granted('team.notice', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if v_title = '' or length(v_title) > 120 then return jsonb_build_object('error', 'bad-title'); end if;
  if v_body is not null and length(v_body) > 1000 then return jsonb_build_object('error', 'bad-body'); end if;
  perform pg_advisory_xact_lock(hashtext('team-notice-send:' || me.id::text));
  select count(*), min(tn.created_at) into v_sent, v_first
    from (select x.created_at from public.team_notices x
           where x.sent_by = me.id and x.created_at > now() - interval '1 hour'
           order by x.created_at desc limit 10) tn;
  if v_sent >= 10 then
    return jsonb_build_object('error', 'too-many', 'limit', 10, 'next', v_first + interval '1 hour');
  end if;
  select coalesce(array_agg(m.id order by m.name), '{}') into v_to
    from public.team_members m
   where m.active and not coalesce(m.system, false) and m.id <> me.id
     and (p_to is null or m.id = any(p_to));
  n := coalesce(array_length(v_to, 1), 0);
  if n = 0 then return jsonb_build_object('error', 'no-one'); end if;
  insert into public.team_notices (title, body, to_all, recipients, sent_by, sent_by_name)
  values (v_title, v_body, p_to is null, v_to, me.id, me.name)
  returning id into v_id;
  insert into public.ops_notifications (team_member_id, kind, title, body, notice_id, from_name)
  select x, 'notice', v_title, v_body, v_id, me.name from unnest(v_to) as x;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Notices',
    'Sent to ' || case when p_to is null then 'all colleagues (' || n || ')'
                       when n = 1 then '1 colleague' else n || ' colleagues' end || ': ' || v_title);
  return jsonb_build_object('ok', true, 'id', v_id, 'count', n);
end $$;
revoke all on function public.team_notice_send(text, text, uuid[]) from public, anon;
grant execute on function public.team_notice_send(text, text, uuid[]) to authenticated;
-- END OF TEN NOTICES AN HOUR ------------------------------------------------

select public.functions_tidy();
