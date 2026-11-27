-- ===========================================================================
-- PERSONNEL NUMBERS MASKED (2026-11-27)
-- ===========================================================================
-- WHY: session J's review of 26 Nov, finding 3. The ten hidden numbers
-- (NRIC, Old IC, Passport, Immigration, Spouse NRIC, Spouse Income Tax,
-- Account number, EPF, SOCSO, Income Tax) were sent whole by
-- personnel_get and personnel_mine and only drawn masked by the page, so
-- the network answer held them and the reveal record could be bypassed.
-- The user chose option A (27 Nov, through the coordinator).
-- WHAT IT CHANGES: personnel_json answers each hidden number as its last
-- four characters under `hidden`, never in `data`; personnel_revealed
-- answers the value with its filed reveal; personnel_save and
-- personnel_save_mine take `_keep` (hidden numbers the sheet never showed)
-- and keep each as stored, so the mask is never written back. New:
-- personnel_hidden() (the one list), personnel_kept(). No table change.
-- A sheet open from before sends no `_keep`: every hidden number its save
-- lacks is kept, so a tab that never held the numbers cannot clear them.
-- ROLLBACK: re-run personnel_json from 2026-11-24-personnel-prefill.sql,
-- personnel_revealed from 2026-11-25-personal-details-revealed.sql, and
-- personnel_save and personnel_save_mine from 2026-11-16-personnel-records.sql;
-- the two new functions may stay.
-- Safe to run twice.

create or replace function public.personnel_hidden()
returns text[]
language sql immutable set search_path = public as $$
  select array['nric', 'old_ic', 'passport', 'immigration_no', 'spouse_ic', 'spouse_tax',
               'bank_account', 'epf_no', 'socso_no', 'tax_no']
$$;

create or replace function public.personnel_kept(p_member uuid, p_data jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_out jsonb; v_old jsonb; k text;
begin
  if jsonb_typeof(p_data) is distinct from 'object' then return p_data; end if;
  v_out := p_data - '_keep';
  select r.data into v_old from public.personnel_records r where r.team_member_id = p_member;
  if v_old is null then return v_out; end if;
  -- A hidden number the sheet never showed is kept as stored; a number
  -- typed or cleared is the sheet's (review J3). A sheet from before this
  -- band sends no `_keep` and never held the numbers: every one it lacks
  -- is kept.
  for k in select x from jsonb_array_elements_text(case when jsonb_typeof(p_data -> '_keep') = 'array' then p_data -> '_keep'
                                                      else to_jsonb(public.personnel_hidden()) end) x loop
    if k = any (public.personnel_hidden()) and not (v_out ? k) and v_old ? k then
      v_out := v_out || jsonb_build_object(k, v_old -> k);
    end if;
  end loop;
  return v_out;
end $$;

create or replace function public.personnel_json(p_member uuid, p_team boolean)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.personnel_records; t public.team_members; s public.personnel_salaries;
begin
  select * into t from public.team_members where id = p_member;
  select * into r from public.personnel_records where team_member_id = p_member;
  select * into s from public.personnel_salaries where team_member_id = p_member;
  return jsonb_build_object('ok', true, 'member', p_member, 'name', t.name,
    -- The ten hidden numbers leave as their last four characters alone
    -- (review J3): the value is read only through personnel_revealed.
    'data', coalesce(r.data, '{}'::jsonb) - public.personnel_hidden(),
    'hidden', (select coalesce(jsonb_object_agg(k, case when char_length(v) > 4 then right(v, 4) else '' end), '{}'::jsonb)
                 from jsonb_each_text(coalesce(r.data, '{}'::jsonb)) x(k, v)
                where k = any (public.personnel_hidden()) and btrim(coalesce(v, '')) <> ''),
    'prefill', jsonb_strip_nulls(jsonb_build_object(
      'email', nullif(btrim(coalesce(t.email, '')), ''),
      'mobile', nullif(btrim(coalesce(t.mobile, '')), ''))),
    'files', coalesce((select jsonb_object_agg(k, jsonb_build_object('at', v ->> 'at', 'type', v ->> 'type'))
                         from jsonb_each(coalesce(r.files, '{}'::jsonb)) x(k, v)), '{}'::jsonb),
    'consent_at', r.consent_at, 'declared_name', r.declared_name, 'declared_at', r.declared_at,
    'requested_at', r.requested_at, 'updated_at', r.updated_at,
    'updated_by', (select u.name from public.team_members u where u.id = r.updated_by),
    'join_date', r.join_date, 'employee_status', r.employee_status, 'employee_type', r.employee_type,
    'probation_months', r.probation_months, 'contract_end', r.contract_end,
    'confirm_date', public.personnel_confirm_date(r.join_date, r.probation_months),
    'superior_id', case when p_team then r.superior_id end,
    'salary_set', case when p_team then (s.probation is not null or s.confirmed is not null) end,
    'missing', to_jsonb(public.personnel_missing(coalesce(r.data, '{}'::jsonb))));
end $$;


create or replace function public.personnel_revealed(p_member uuid, p_field text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members; t public.team_members; g jsonb; v_label text; v_line text;
begin
  if p_member is null then
    g := public.perf_mine_gate();
    if g is not null then return g; end if;
    me := public.ops_me();
    t := me;
  else
    if not public.ops_granted('team.personnel', 'work') then return jsonb_build_object('error', 'denied'); end if;
    me := public.ops_me();
    select * into t from public.team_members x where x.id = p_member;
    if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  end if;
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_field is null or not (p_field = any (public.personnel_hidden())) then
    return jsonb_build_object('error', 'bad-field');
  end if;
  v_label := public.personnel_fields() -> p_field ->> 1;
  v_line := v_label || ' shown';
  if not exists (select 1 from public.activity_log a
                  where a.action = 'team.revealed' and a.actor = me.name and a.subject = t.name and a.detail = v_line
                    and a.created_at > now() - interval '1 minute') then
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.revealed', t.name, v_line);
  end if;
  -- The value itself, answered only here, each time filed above.
  return jsonb_build_object('ok', true,
    'value', (select r.data ->> p_field from public.personnel_records r where r.team_member_id = t.id));
end $$;


create or replace function public.personnel_save(p_member uuid, p_data jsonb, p_expected timestamptz)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare me public.team_members; t public.team_members; r public.personnel_records; c jsonb; what text;
begin
  if not public.ops_granted('team.personnel', 'work') then return jsonb_build_object('error', 'denied'); end if;
  me := public.ops_me();
  select * into t from public.team_members where id = p_member;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if t.erased_at is not null then return jsonb_build_object('error', 'erased'); end if;
  c := public.personnel_clean(public.personnel_kept(p_member, p_data));
  if c ? 'error' then return c; end if;
  insert into public.personnel_records (team_member_id) values (p_member) on conflict (team_member_id) do nothing;
  select * into r from public.personnel_records where team_member_id = p_member for update;
  if p_expected is not null and r.updated_at > p_expected + interval '1 millisecond' then
    return jsonb_build_object('error', 'stale', 'record', public.personnel_json(p_member, true));
  end if;
  what := public.personnel_changed(r.data, c -> 'data');
  if what is null then return public.personnel_json(p_member, true); end if;
  update public.personnel_records set data = c -> 'data', updated_at = now(), updated_by = me.id
   where team_member_id = p_member;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(me.name, 'admin'), 'team.edited', t.name, 'Employee record: ' || what);
  return public.personnel_json(p_member, true);
end $$;


create or replace function public.personnel_save_mine(p_data jsonb, p_consent boolean, p_name text, p_expected timestamptz)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare g jsonb; me public.team_members; r public.personnel_records; c jsonb; miss text[];
        v_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')); what text;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  me := public.ops_me();
  c := public.personnel_clean(public.personnel_kept(me.id, p_data));
  if c ? 'error' then return c; end if;
  miss := public.personnel_missing(c -> 'data');
  if cardinality(miss) > 0 then return jsonb_build_object('error', 'incomplete', 'missing', to_jsonb(miss)); end if;
  if not coalesce(p_consent, false) then return jsonb_build_object('error', 'no-consent'); end if;
  if char_length(v_name) < 2 or char_length(v_name) > 100 then return jsonb_build_object('error', 'bad-name'); end if;
  insert into public.personnel_records (team_member_id) values (me.id) on conflict (team_member_id) do nothing;
  select * into r from public.personnel_records where team_member_id = me.id for update;
  if p_expected is not null and r.updated_at > p_expected + interval '1 millisecond' then
    return jsonb_build_object('error', 'stale', 'record', public.personnel_json(me.id, false));
  end if;
  what := public.personnel_changed(r.data, c -> 'data');
  update public.personnel_records set data = c -> 'data', consent_at = now(), declared_name = v_name,
         declared_at = now(), updated_at = now(), updated_by = me.id
   where team_member_id = me.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(me.name, 'colleague'), 'team.edited', me.name,
          'Employee record submitted' || coalesce(': ' || what, ''));
  return public.personnel_json(me.id, false);
end $$;


revoke all on function public.personnel_hidden() from public, anon, authenticated;
revoke all on function public.personnel_kept(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.personnel_json(uuid, boolean) from public, anon, authenticated;
revoke all on function public.personnel_revealed(uuid, text) from public, anon;
grant execute on function public.personnel_revealed(uuid, text) to authenticated;
revoke all on function public.personnel_save(uuid, jsonb, timestamptz) from public, anon;
grant execute on function public.personnel_save(uuid, jsonb, timestamptz) to authenticated;
revoke all on function public.personnel_save_mine(jsonb, boolean, text, timestamptz) from public, anon;
grant execute on function public.personnel_save_mine(jsonb, boolean, text, timestamptz) to authenticated;
