-- ===========================================================================
-- ADMIN REVIEWS OWN REPORT — an admin submitting a report may name
-- themselves as its reviewer. 2026-10-16. Safe to run twice. Rollback at the
-- foot. Mirrored byte for byte in supabase/schema.sql under the same banner;
-- tests/smsql.js compares the two. Runs after REPORT AUDIT.
--
-- WHAT CHANGED (the user, 2026-10-16: "if i am admin, u still need me to
-- assign someone else which violates the hierarchy")
--   1. `sm_report_reviewers`: for a report an admin submits (or submitted),
--      the admin is offered too (`self`), chosen unless a reviewer is set.
--      Anyone else is never offered their own report.
--   2. `sm_report_submit`: an admin may name themselves (`self-review` stays
--      for everyone else); the record reads Reviewer: themselves (admin).
--   3. `sm_report_assign`: a report an admin submitted may be handed back
--      to that admin.
--   Confirming is unchanged: an admin already confirms their own report
--   after a question saying nobody else checked it.
--
-- ROLLBACK
--   Run the three functions again from 2026-10-04-report-reviewer.sql
--   (`sm_report_reviewers`, `sm_report_assign`) and 2026-10-09-report-audit.sql
--   (`sm_report_submit`); each is safe to run again.
-- ===========================================================================

create or replace function public.sm_report_reviewers(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  author uuid;
  last_id uuid;
  author_admin boolean;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  author := case when r.status = 'review' then r.submitted_by else me.id end;
  author_admin := exists (select 1 from public.team_members a
                           where a.id = author and (coalesce(a.is_admin, false) or a.role = 'admin'));
  select x.reviewer_id into last_id from public.sm_reports x
   where x.client_id = r.client_id and x.reviewer_id is not null and x.reviewer_id is distinct from author
     and public.sm_report_may_review(x.reviewer_id)
   order by coalesce(x.submitted_at, x.updated_at) desc nulls last limit 1;
  return jsonb_build_object('reviewers', coalesce((
    select jsonb_agg(jsonb_build_object('id', m.id, 'name', m.name, 'code', m.staff_code,
             'self', m.id = author,
             'last', m.id = coalesce(r.reviewer_id, case when author_admin then author end, last_id))
             order by m.staff_code nulls last, m.name)
      from public.team_members m
     where (m.id is distinct from author or author_admin) and public.sm_report_may_review(m.id)), '[]'::jsonb));
end $$;
revoke all on function public.sm_report_reviewers(uuid) from public, anon, authenticated;
grant execute on function public.sm_report_reviewers(uuid) to authenticated;

/* `p_reason` is the reason a late submit, or one past the month's gate,
   gives; it is read from MONTH REPORTS (2026-10-04) on. The Report audit
   (2026-10-09) holds a linked report until Meta's figures match. */
create or replace function public.sm_report_submit(p_id uuid, p_reviewer uuid default null, p_reason text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  cname text;
  g jsonb;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_gate text;
  v_late text;
  v_extra text := '';
  v_audit text;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'draft' then return jsonb_build_object('error', 'not-draft', 'status', r.status); end if;
  if r.kind = 'ads' then
    if not exists (select 1 from public.sm_report_ads where report_id = p_id) then
      return jsonb_build_object('error', 'no-ads');
    end if;
  else
    if not exists (select 1 from public.sm_report_platforms where report_id = p_id) then
      return jsonb_build_object('error', 'no-platforms');
    end if;
    if not exists (select 1 from public.sm_report_posts where report_id = p_id) then
      return jsonb_build_object('error', 'no-posts');
    end if;
  end if;
  v_audit := public.sm_report_audit_blocks(p_id, null);
  if v_audit is not null then return jsonb_build_object('error', v_audit); end if;
  g := public.sm_report_gate(p_id);
  if coalesce((g ->> 'applies')::boolean, false) then
    if not (g ->> 'ok')::boolean then
      if not (g ->> 'may_override')::boolean or v_reason is null then
        return jsonb_build_object('error', 'month-gate', 'missing', g -> 'missing', 'planned', g -> 'planned',
                                  'made', g -> 'made', 'may_override', g -> 'may_override');
      end if;
      v_gate := left(v_reason, 500);
    end if;
    if (g ->> 'late')::boolean then
      if v_reason is null then
        return jsonb_build_object('error', 'late-reason', 'due', g -> 'due');
      end if;
      v_late := left(v_reason, 500);
    end if;
  end if;
  if p_reviewer is null then return jsonb_build_object('error', 'no-reviewer'); end if;
  if p_reviewer = me.id and not (coalesce(me.is_admin, false) or me.role = 'admin') then
    return jsonb_build_object('error', 'self-review');
  end if;
  if not public.sm_report_may_review(p_reviewer) then return jsonb_build_object('error', 'bad-reviewer'); end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set status = 'review', submitted_by = me.id, submitted_at = now(),
    reviewer_id = p_reviewer, return_note = null, confirmed_by = null, confirmed_at = null,
    late_reason = v_late, gate_note = v_gate where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  if v_gate is not null then v_extra := v_extra || ' · Past the month''s gate: ' || v_gate; end if;
  if v_late is not null and v_gate is distinct from v_late then v_extra := v_extra || ' · Late: ' || v_late;
  elsif v_late is not null then v_extra := v_extra || ' · Late'; end if;
  perform public.sm_report_log(p_id, 'report.submitted',
    case when p_reviewer = me.id then 'Reviewer: themselves (admin)'
         else 'Reviewer: ' || (select name from public.team_members where id = p_reviewer) end || v_extra);
  select c.name into cname from public.clients c where c.id = r.client_id;
  perform public.sm_report_notify(p_reviewer, p_id, 'report.review', 'Report to review',
    cname || ' · ' || public.sm_period_word(r.period_start, r.period_end));
  return jsonb_build_object('ok', true, 'status', 'review');
end $$;
revoke all on function public.sm_report_submit(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.sm_report_submit(uuid, uuid, text) to authenticated;

create or replace function public.sm_report_assign(p_id uuid, p_reviewer uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  was text;
  cname text;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'review' then return jsonb_build_object('error', 'not-in-review', 'status', r.status); end if;
  if not (me.id = r.submitted_by or me.id is not distinct from r.reviewer_id
          or coalesce(me.is_admin, false) or me.role = 'admin') then
    return jsonb_build_object('error', 'denied');
  end if;
  if p_reviewer is null then return jsonb_build_object('error', 'no-reviewer'); end if;
  if p_reviewer = r.submitted_by and not exists (
       select 1 from public.team_members a
        where a.id = r.submitted_by and (coalesce(a.is_admin, false) or a.role = 'admin')) then
    return jsonb_build_object('error', 'self-review');
  end if;
  if p_reviewer is not distinct from r.reviewer_id then return jsonb_build_object('error', 'same-reviewer'); end if;
  if not public.sm_report_may_review(p_reviewer) then return jsonb_build_object('error', 'bad-reviewer'); end if;
  select name into was from public.team_members where id = r.reviewer_id;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set reviewer_id = p_reviewer where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.reassigned',
    'Reviewer: ' || coalesce(was, 'not set') || ' → ' || (select name from public.team_members where id = p_reviewer));
  select c.name into cname from public.clients c where c.id = r.client_id;
  perform public.sm_report_notify(p_reviewer, p_id, 'report.review', 'Report to review',
    cname || ' · ' || public.sm_period_word(r.period_start, r.period_end));
  return jsonb_build_object('ok', true, 'status', 'review');
end $$;
revoke all on function public.sm_report_assign(uuid, uuid) from public, anon, authenticated;
grant execute on function public.sm_report_assign(uuid, uuid) to authenticated;

-- END OF ADMIN REVIEWS OWN REPORT -----------------------------------------

select public.functions_tidy();
