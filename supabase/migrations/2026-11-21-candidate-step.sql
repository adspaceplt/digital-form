-- ===========================================================================
-- CANDIDATE STEP (2026-11-21)
-- ===========================================================================
-- WHY: the user, 2026-11-21 ("Yes"): Team's Hiring list read Invited for a
-- candidate who had already chosen an interview time on their page, so the
-- team could not see who was waiting on them. A candidate's row now reads
-- the candidate's latest step while it waits on the team, and the candidate
-- stays in the Dashboard's Waiting for you until a colleague acts.
--
-- WHAT IT CHANGES
--   * `hiring_step(p_candidate)` (no caller's): the candidate's latest step
--     on their page that waits on the team, `{step, at}`, else null:
--     `picked` (a time chosen: Approve), `none` (other times asked for:
--     Send new times), `accepted` (an offer accepted) and `signed` (a
--     contract signed, online or marked: Confirm), `declined` (an offer
--     declined with no offer made since: a decision). Only the latest open
--     invitation is read; a candidate hired, closed, in the talent pool or
--     removed waits on nobody.
--   * `hiring_row` (restated whole from HIRING) answers `step` and
--     `step_at`, so the list and a record read it.
--   * `hiring_waiting()` (authenticated): the candidates waiting on the
--     caller, the ones they may act on: a time chosen, other times asked
--     for or an offer declined to the part and the candidate's Owners; an
--     offer accepted or a contract signed to the part alone (Confirm is
--     the part's). Never a candidate's email or note.
--
-- ORDER: this file, then the pages. An old page ignores `step`; a new page
-- on the old database reads no step and draws the stage as before, and its
-- Waiting for you asks `hiring_waiting`, which a database without it
-- refuses (said as Could not load: Hiring.). Safe to run twice.
--
-- ROLLBACK: run `hiring_row` from HIRING again; drop `hiring_waiting()`
-- and `hiring_step(uuid)`.
-- ===========================================================================

create or replace function public.hiring_step(p_candidate uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select x.j
    from public.hiring_candidates c
    cross join lateral (
      select jsonb_build_object('step', s.step, 'at', s.at) j, s.at
        from (
          select case i.state when 'picked' then 'picked' else 'none' end step,
                 case i.state when 'picked' then coalesce(i.picked_at, i.updated_at) else i.updated_at end at
            from (select h.state, h.picked_at, h.updated_at from public.hiring_interviews h
                   where h.candidate_id = c.id and h.state not in ('cancelled', 'replaced')
                   order by h.invited_at desc limit 1) i
           where i.state in ('picked', 'none')
          union all
          select case d.kind when 'offer' then 'accepted' else 'signed' end, coalesce(d.signed_at, d.updated_at)
            from public.hiring_docs d
           where d.candidate_id = c.id and d.state = 'signed'
          union all
          select 'declined', d.answered_at
            from public.hiring_docs d
           where d.candidate_id = c.id and d.kind = 'offer' and d.state = 'declined' and d.answered_at is not null
             and c.stage = 'offer'
             and not exists (select 1 from public.hiring_docs n where n.candidate_id = c.id and n.kind = 'offer'
                              and n.id <> d.id and n.made_at > d.answered_at)
        ) s
       order by s.at desc nulls last
       limit 1
    ) x
   where c.id = p_candidate and c.removed_at is null and c.stage not in ('hired', 'closed', 'pool');
$$;
revoke all on function public.hiring_step(uuid) from public, anon, authenticated;

create or replace function public.hiring_row(c public.hiring_candidates, p_role text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', c.id, 'name', c.name, 'position', c.position, 'source', c.source, 'stage', c.stage,
    'created_at', c.created_at, 'last_step_at', c.last_step_at, 'removed_at', c.removed_at, 'role', p_role,
    'owners', coalesce((select jsonb_agg(t.name order by t.name) from public.hiring_people p
                         join public.team_members t on t.id = p.team_member_id
                        where p.candidate_id = c.id and p.role = 'owner'), '[]'::jsonb))
    || coalesce((select jsonb_build_object('step', s->>'step', 'step_at', s->'at') from public.hiring_step(c.id) s
                  where s is not null), '{}'::jsonb);
$$;
revoke all on function public.hiring_row(public.hiring_candidates, text) from public, anon, authenticated;

create or replace function public.hiring_waiting()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_admin boolean := public.ops_granted('team.hiring', 'work');
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('id', w.id, 'name', w.name, 'position', w.position, 'step', w.s->>'step', 'at', w.s->'at')
                     order by w.s->>'at')
      from (
        select c.id, c.name, c.position, public.hiring_step(c.id) s,
               exists (select 1 from public.hiring_people p where p.candidate_id = c.id and p.team_member_id = me.id and p.role = 'owner') own
          from public.hiring_candidates c
         where c.removed_at is null and c.stage not in ('hired', 'closed', 'pool')
           and (v_admin or exists (select 1 from public.hiring_people p where p.candidate_id = c.id
                                     and p.team_member_id = me.id and p.role = 'owner'))
      ) w
     where w.s is not null
       and (v_admin or (w.own and w.s->>'step' in ('picked', 'none', 'declined')))), '[]'::jsonb));
end $$;
revoke all on function public.hiring_waiting() from public, anon;
grant execute on function public.hiring_waiting() to authenticated;

-- END OF CANDIDATE STEP -------------------------------------------------------

select public.functions_tidy();
