-- ===========================================================================
-- HIRING RECORDS HELD (2026-11-17)
-- ===========================================================================
-- WHY: the review of the releases since #1134 (2026-11-17, the user: "fix
-- all"), findings 1, 2, 8, 9 and 11.
--
-- WHAT IT CHANGES
--   * `hiring_file_ok`: an Interviewer reads the candidate's CV alone. The
--     sealed contract, a signed scan and the stamp (the pay, the signature
--     and the identity number) stay with the Owner and the Hiring part, as
--     the database's own reads already held them.
--   * `hiring_delete` refuses `has-contract` for a hired candidate, or one
--     holding a signed or confirmed document: an employment record is
--     removed, never deleted.
--   * `hiring_decide`: any outcome but Proceed, Reopen included, withdraws
--     the documents still waiting on the candidate's answer, so an offer the
--     team decided against can no longer be signed.
--   * `hiring_serials_kept` (RLS on, no policy, no grant) keeps every
--     reference a deleted document held (trigger `hiring_docs_serial_kept`),
--     and `hiring_doc_serial` counts it, so a reference is never given twice
--     and /verify/ never reads an old one as another's.
--   * `hiring_make_colleague` asks Team Full Access as Add member does
--     (`team-access`), and answers a refused insert in words;
--     `hiring_hire_state`'s `may` asks the same, so the button is not drawn.
--
-- ORDER: this file (connector), then the pages. A page from before reads
-- `has-contract` and `team-access` as an error line. Safe to run twice.
--
-- ROLLBACK: run the six functions from their bands before (HIRING, HIRING
-- OUTCOMES, HIRING OFFERS, HIRING ONBOARDING, HR DOCUMENTS VERIFIED) again;
-- the table and its trigger may stay.
-- ===========================================================================


-- HIRING RECORDS HELD — an Interviewer reads the CV alone; a contract is never deleted.

create table if not exists public.hiring_serials_kept (
  serial     text primary key,
  kept_at    timestamptz not null default now()
);
alter table public.hiring_serials_kept enable row level security;
revoke all on table public.hiring_serials_kept from public, anon, authenticated;

/* A deleted document's reference is kept, so it is never given again. */
create or replace function public.hiring_docs_serial_kept()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.serial is not null then
    insert into public.hiring_serials_kept (serial) values (old.serial) on conflict (serial) do nothing;
  end if;
  return old;
end $$;
revoke all on function public.hiring_docs_serial_kept() from public, anon, authenticated;
drop trigger if exists hiring_docs_serial_kept on public.hiring_docs;
create trigger hiring_docs_serial_kept before delete on public.hiring_docs
  for each row execute function public.hiring_docs_serial_kept();
insert into public.hiring_serials_kept (serial)
  select distinct d.serial from public.hiring_docs d where d.serial is not null
  on conflict (serial) do nothing;

/* The next reference of a kind and month: ADHR/OFR{YYMM}{NNN} for an
   offer, ADHR/EMP{YYMM}{NNN} for a contract, under the kind's lock; a
   reference once given is never given again, a deleted one included. */
create or replace function public.hiring_doc_serial(p_kind text)
returns text language plpgsql volatile security definer set search_path = public as $$
declare
  v_pre text := 'ADHR/' || case p_kind when 'offer' then 'OFR' else 'EMP' end || to_char(now() at time zone 'Asia/Kuala_Lumpur', 'YYMM');
  v_n int;
begin
  perform pg_advisory_xact_lock(hashtext('hiring_doc_serial:' || p_kind));
  select coalesce(max(right(d.serial, 3)::int), 0) + 1 into v_n
    from (select d.serial from public.hiring_docs d where d.serial like v_pre || '___'
          union all select k.serial from public.hiring_serials_kept k where k.serial like v_pre || '___') d;
  if v_n > 999 then raise exception 'no-serial'; end if;
  return v_pre || lpad(v_n::text, 3, '0');
end $$;
revoke all on function public.hiring_doc_serial(text) from public, anon, authenticated;


/* The sealed copy is read by HR Letters at View too, the sealed file of a
   confirmed document alone. The candidate's Owner reads and writes every
   file in the folder; an Interviewer reads the CV alone, never a contract,
   a scan or a stamp (they carry the pay and the identity number). */
create or replace function public.hiring_file_ok(p_name text, p_write boolean)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_id uuid;
  v_role text;
begin
  begin
    v_id := split_part(coalesce(p_name, ''), '/', 1)::uuid;
  exception when others then return false;
  end;
  v_role := public.hiring_role(v_id);
  if v_role is null then
    return not coalesce(p_write, false) and public.register_may('hr', 'view')
       and exists (select 1 from public.hiring_docs x
                    where x.candidate_id = v_id and x.seal_path = p_name and x.confirmed_at is not null);
  end if;
  if v_role in ('admin', 'owner') then return true; end if;
  return not coalesce(p_write, false)
     and exists (select 1 from public.hiring_candidates c where c.id = v_id and c.cv_path = p_name);
end $$;
revoke all on function public.hiring_file_ok(text, boolean) from public, anon;
grant execute on function public.hiring_file_ok(text, boolean) to authenticated;

create or replace function public.hiring_delete(p_id uuid, p_name text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  c public.hiring_candidates;
begin
  if me.id is null or not public.ops_granted('team.hiring', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = p_id for update;
  if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if c.removed_at is null then return jsonb_build_object('error', 'not-removed'); end if;
  if lower(btrim(coalesce(p_name, ''))) <> lower(c.name) then return jsonb_build_object('error', 'bad-name'); end if;
  /* A hired candidate, or one holding a signed or confirmed document, is
     an employment record: removed, never deleted. */
  if c.stage = 'hired' or c.member_id is not null or exists (select 1 from public.hiring_docs d
       where d.candidate_id = c.id and (d.state in ('signed', 'confirmed') or d.confirmed_at is not null)) then
    return jsonb_build_object('error', 'has-contract');
  end if;
  delete from public.hiring_candidates where id = p_id;
  return jsonb_build_object('ok', true, 'cv_path', c.cv_path);
end $$;
grant execute on function public.hiring_delete(uuid, text) to authenticated;

/* The part's or the Owner's decision: Proceed, Keep in talent pool, Not
   proceed, or Reopen (the way back). Any outcome but Proceed withdraws
   the documents still waiting on the candidate's answer. */
create or replace function public.hiring_decide(p_id uuid, p_outcome text, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_role text := public.hiring_role(p_id);
  c public.hiring_candidates;
  v_back text;
begin
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_outcome, '') not in ('proceed', 'pool', 'not', 'reopen') then return jsonb_build_object('error', 'bad-outcome'); end if;
  if char_length(coalesce(p_note, '')) > 1000 then return jsonb_build_object('error', 'too-long'); end if;
  select * into c from public.hiring_candidates where id = p_id for update;
  if c.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if c.stage = 'hired' then return jsonb_build_object('error', 'closed'); end if;
  if p_outcome = 'reopen' then
    if c.outcome is null then return jsonb_build_object('ok', true, 'same', true); end if;
    v_back := case when exists (select 1 from public.hiring_interviews i where i.candidate_id = c.id and i.state = 'confirmed') then 'interview'
      when exists (select 1 from public.hiring_interviews i where i.candidate_id = c.id and i.state in ('invited', 'picked', 'none')) then 'invited'
      else 'new' end;
    update public.hiring_candidates set stage = v_back, outcome = null, outcome_note = null, outcome_by = null, outcome_at = null,
      pool_consent = null, pool_until = null, outcome_mail = null, outcome_mail_at = null, last_step_at = now(), updated_at = now()
     where id = c.id;
    update public.hiring_docs set state = 'withdrawn', updated_at = now() where candidate_id = c.id and state = 'sent';
    perform public.hiring_log(c.id, 'candidate.decided', 'Reopened');
    return jsonb_build_object('ok', true, 'was', c.outcome, 'note', c.outcome_note);
  end if;
  if c.outcome = p_outcome then return jsonb_build_object('ok', true, 'same', true); end if;
  update public.hiring_candidates set
    stage = case p_outcome when 'proceed' then 'offer' when 'pool' then 'pool' else 'closed' end,
    outcome = p_outcome, outcome_note = nullif(btrim(coalesce(p_note, '')), ''), outcome_by = me.id, outcome_at = now(),
    pool_consent = case when p_outcome = 'pool' then 'asked' end, pool_until = null, outcome_mail = null, outcome_mail_at = null,
    last_step_at = now(), updated_at = now()
   where id = c.id;
  update public.hiring_interviews set state = 'cancelled', updated_at = now()
   where candidate_id = c.id and p_outcome <> 'proceed' and state in ('invited', 'picked', 'none');
  update public.hiring_docs set state = 'withdrawn', updated_at = now()
   where candidate_id = c.id and p_outcome <> 'proceed' and state = 'sent';
  perform public.hiring_log(c.id, 'candidate.decided',
    case p_outcome when 'proceed' then 'Proceed' when 'pool' then 'Keep in talent pool' else 'Not proceed' end);
  return jsonb_build_object('ok', true, 'was', c.outcome, 'email', p_outcome in ('pool', 'not'));
end $$;
grant execute on function public.hiring_decide(uuid, text, text) to authenticated;


/* Whether a candidate can be made a colleague, and what the question opens
   on: the confirmed contract's terms (never the salary). Read by anyone
   on the candidate; the act is the Hiring part's. */
create or replace function public.hiring_hire_state(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  c public.hiring_candidates;
  v_role text := public.hiring_role(p_id);
  ctr public.hiring_docs;
  m public.team_members;
  w public.team_welcome;
begin
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.hiring_candidates where id = p_id;
  if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if c.member_id is not null then
    select * into m from public.team_members where id = c.member_id;
    select * into w from public.team_welcome where member_id = c.member_id;
    return jsonb_build_object('ok', true, 'made', true, 'member', jsonb_strip_nulls(jsonb_build_object(
      'id', m.id, 'name', m.name, 'staff_code', m.staff_code, 'email', m.email, 'active', m.active,
      'first_day', w.first_day, 'hired_at', c.hired_at, 'welcomed_at', w.acked_at)));
  end if;
  select * into ctr from public.hiring_docs where candidate_id = c.id and kind = 'contract' and state = 'confirmed'
   order by confirmed_at desc limit 1;
  return jsonb_build_object('ok', true, 'made', false,
    'ready', ctr.id is not null and exists (select 1 from public.hiring_docs d where d.candidate_id = c.id and d.kind = 'offer' and d.state = 'confirmed')
             and c.removed_at is null,
    'may', public.ops_granted('team.hiring', 'work') and public.allowed('team', 'manage'),
    'terms', case when ctr.id is not null then jsonb_strip_nulls(jsonb_build_object('position', ctr.terms->>'position',
      'start', ctr.terms->>'start', 'type', ctr.terms->>'type')) end);
end $$;
revoke all on function public.hiring_hire_state(uuid) from public, anon;
grant execute on function public.hiring_hire_state(uuid) to authenticated;


/* Make colleague: the Hiring part, the offer and the contract confirmed.
   The colleague is added as Add member adds one (every guard on
   team_members holds), their employment terms taken from the contract,
   their first day and direct manager kept for the Welcome Kit. */
create or replace function public.hiring_make_colleague(p_id uuid, p_values jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  c public.hiring_candidates;
  ctr public.hiring_docs;
  v jsonb := coalesce(p_values, '{}'::jsonb);
  v_email text := lower(btrim(coalesce(v->>'email', '')));
  v_role text := btrim(coalesce(v->>'role', ''));
  v_staff text := upper(btrim(coalesce(v->>'staff_code', '')));
  v_dept text := btrim(coalesce(v->>'department', ''));
  v_pos text := btrim(coalesce(v->>'designation', ''));
  v_day date;
  v_dm uuid;
  v_mobile text;
  v_type text;
  v_id uuid;
begin
  if me.id is null or not public.ops_granted('team.hiring', 'work') then return jsonb_build_object('error', 'denied'); end if;
  /* A sign-in is made as Add member makes one: Team Full Access too. */
  if not public.allowed('team', 'manage') then return jsonb_build_object('error', 'team-access'); end if;
  select * into c from public.hiring_candidates where id = p_id for update;
  if c.id is null or c.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if c.member_id is not null then return jsonb_build_object('ok', true, 'id', c.member_id, 'again', true); end if;
  select * into ctr from public.hiring_docs where candidate_id = c.id and kind = 'contract' and state = 'confirmed'
   order by confirmed_at desc limit 1;
  if ctr.id is null or not exists (select 1 from public.hiring_docs d where d.candidate_id = c.id and d.kind = 'offer' and d.state = 'confirmed') then
    return jsonb_build_object('error', 'not-ready');
  end if;
  begin
    v_day := nullif(v->>'first_day', '')::date;
    v_dm := nullif(v->>'dm', '')::uuid;
  exception when others then return jsonb_build_object('error', 'bad-request');
  end;
  if char_length(v_email) not between 5 and 160 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return jsonb_build_object('error', 'bad-email'); end if;
  if not exists (select 1 from public.team_roles r where r.slug = v_role) then return jsonb_build_object('error', 'bad-role'); end if;
  if v_staff !~ '^[A-Z0-9]{3,8}$' then return jsonb_build_object('error', 'bad-staff'); end if;
  if not exists (select 1 from public.departments d where d.key = v_dept and d.active) then return jsonb_build_object('error', 'bad-department'); end if;
  if char_length(v_pos) not between 2 and 80 then return jsonb_build_object('error', 'bad-position'); end if;
  if v_day is null or v_day < date '2023-08-14' or v_day > date '2099-12-31' then return jsonb_build_object('error', 'bad-day'); end if;
  if v_dm is null or not exists (select 1 from public.team_members t where t.id = v_dm and t.active) then return jsonb_build_object('error', 'bad-dm'); end if;
  if exists (select 1 from public.team_members t where lower(t.email) = v_email and t.removed_at is null) then
    return jsonb_build_object('error', 'taken', 'field', 'email');
  end if;
  if exists (select 1 from public.team_members t where t.staff_code = v_staff and t.removed_at is null) then
    return jsonb_build_object('error', 'taken', 'field', 'staff_code');
  end if;
  if exists (select 1 from public.team_members t where lower(t.name) = lower(c.name) and t.removed_at is null) then
    return jsonb_build_object('error', 'taken', 'field', 'name');
  end if;
  v_mobile := case when char_length(regexp_replace(coalesce(c.phone, ''), '\D', '', 'g')) between 8 and 15 then btrim(c.phone) end;
  begin
    insert into public.team_members (name, email, role, staff_code, designation, department, mobile, active)
    values (c.name, v_email, v_role, v_staff, v_pos, v_dept, v_mobile, true)
    returning id into v_id;
  exception
    when unique_violation then return jsonb_build_object('error', 'taken');
    when raise_exception or insufficient_privilege then return jsonb_build_object('error', 'refused', 'reason', sqlerrm);
  end;
  v_type := ctr.terms->>'type';
  insert into public.personnel_records (team_member_id, join_date, employee_status, employee_type, probation_months,
                                        contract_end, superior_id, updated_by)
  values (v_id, v_day,
    case v_type when 'permanent' then 'Permanent' when 'contract' then 'Contract' when 'intern' then 'Interns' when 'part_time' then 'Part time' end,
    case v_type when 'permanent' then 'FT' when 'part_time' then 'PT' else 'CT' end,
    coalesce(nullif(ctr.terms->>'probation_months', '')::int, 0),
    nullif(ctr.terms->>'end', '')::date, v_dm, me.id)
  on conflict (team_member_id) do nothing;
  insert into public.team_welcome (member_id, first_day, dm_id, made_by) values (v_id, v_day, v_dm, me.id)
  on conflict (member_id) do nothing;
  insert into public.team_onboarding (member_id) values (v_id) on conflict (member_id) do nothing;
  update public.hiring_candidates set stage = 'hired', member_id = v_id, hired_at = now(), last_step_at = now(), updated_at = now()
   where id = c.id;
  perform public.hiring_log(c.id, 'candidate.hired', v_staff || ' · first day ' || public.register_day(v_day));
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.added', c.name, v_email || ' · ' || coalesce((select r.name from public.team_roles r where r.slug = v_role), v_role)
    || ' · made from a candidate');
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke all on function public.hiring_make_colleague(uuid, jsonb) from public, anon;
grant execute on function public.hiring_make_colleague(uuid, jsonb) to authenticated;


-- END OF HIRING RECORDS HELD ------------------------------------------------

select public.functions_tidy();
