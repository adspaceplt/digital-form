-- ===========================================================================
-- HIRING ONBOARDING — Make colleague, the Welcome Kit at first sign-in, and
-- the colleague's onboarding checklist (2026-11-17, release H2 step E1)
-- ===========================================================================
-- WHY (HR-SPEC.md decisions 1, 7; the mockups the user approved on
-- 2026-11-17, "approved"): once a candidate's Employment Offer and
-- Employment Contract are both confirmed, the Hiring part makes them a
-- colleague (the Lark company email typed, Lark having no API); their first
-- sign-in shows the Welcome Kit before the Handbook's required files; and
-- the colleague's record keeps the onboarding checklist, the assets issued
-- and returned, and the internal entry and exit steps.
--
-- WHAT IT CHANGES
--   * `hiring_candidates.member_id`, `hired_at`.
--   * `team_welcome` (a new colleague's first day and direct manager, and
--     when they acknowledged the kit), `welcome_kit` (the team's words, a
--     section at a time), `team_onboarding` (the ticks and the assets): RLS
--     on, no policy, no grant.
--   * `hiring_hire_state(p_id)`, `hiring_make_colleague(p_id, p_values)`;
--     `welcome_kit_get()`, `welcome_kit_save(p_sections)` (Business
--     settings); `welcome_kit_mine()`, `welcome_kit_ack()` (the colleague);
--     `onboarding_get(p_member)`, `onboarding_tick(p_member, p_side, p_key,
--     p_on)`, `onboarding_assets_save(p_member, p_assets, p_expected)` (the
--     Hiring or Personnel part).
--   * The Wi-Fi password and the door PIN are never kept: the kit says
--     "Please check with your direct manager.", and a section line naming
--     either is refused (`secret`).
--
-- Never a salary: the terms a colleague is made from are the contract's
-- position, type, start, end and probation (hiring_docs.terms), never
-- `hiring_doc_pay`.
--
-- ORDER: this file (connector), then the pages. Safe to run twice.
-- ROLLBACK: drop the ten functions and three tables, and the two columns of
-- hiring_candidates.
-- ===========================================================================

-- HIRING ONBOARDING -------------------------------------------------------------

alter table public.hiring_candidates add column if not exists member_id uuid references public.team_members(id) on delete set null;
alter table public.hiring_candidates add column if not exists hired_at timestamptz;

create table if not exists public.team_welcome (
  member_id  uuid primary key references public.team_members(id) on delete cascade,
  first_day  date not null check (first_day between date '2023-08-14' and date '2099-12-31'),
  dm_id      uuid references public.team_members(id) on delete set null,
  made_by    uuid references public.team_members(id) on delete set null,
  created_at timestamptz not null default now(),
  acked_at   timestamptz
);
alter table public.team_welcome enable row level security;
revoke all on table public.team_welcome from public, anon, authenticated;

create table if not exists public.welcome_kit (
  id         integer primary key default 1 check (id = 1),
  sections   jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.team_members(id) on delete set null
);
alter table public.welcome_kit enable row level security;
revoke all on table public.welcome_kit from public, anon, authenticated;

create table if not exists public.team_onboarding (
  member_id  uuid primary key references public.team_members(id) on delete cascade,
  ticks      jsonb not null default '{}'::jsonb,
  assets     jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.team_onboarding enable row level security;
revoke all on table public.team_onboarding from public, anon, authenticated;

/* The kit's words, seeded once into an empty table from the team's Welcome
   Kit. A line "Label: value" reads as a fact, any other as a paragraph. */
insert into public.welcome_kit (id, sections)
select 1, jsonb_build_array(
  jsonb_build_object('title', 'Welcome', 'body',
    'You have joined a team that believes every brand has a story worth telling well.' || chr(10) ||
    'Your first few days are about settling in, meeting the people you will work with and getting your tools ready. We would rather you start sharp than start fast.'),
  jsonb_build_object('title', 'About the company', 'body',
    'Company: ADSPACE PLT' || chr(10) || 'Registration No.: 202304002162 (LLP0036103-LGN)' || chr(10) ||
    'Address: 61-02, Jalan Mutiara Emas 2A, Taman Mount Austin, 81100 Johor Bahru, Johor' || chr(10) ||
    'Parking: Outdoor parking, no coupon required' || chr(10) || 'Wi-Fi network: ADunifi / ADunifi_5G' || chr(10) ||
    'Office mobile: +60 18-762 5233' || chr(10) || 'HR matters: hr@adspacestudios.com' || chr(10) ||
    'Management: management@adspacestudios.com'),
  jsonb_build_object('title', 'How we work', 'body',
    'WhatsApp: Quick, day-to-day messages, internally and with clients' || chr(10) ||
    'Lark: Your company email, documents and anything that needs a record' || chr(10) ||
    'Zoom: Video meetings and client calls' || chr(10) ||
    'Google Drive: Shared files and collaboration, owned by the ADspace account' || chr(10) ||
    'AutoCount HRMS: Payroll, payslips, e-leave and tax profiles' || chr(10) ||
    'Bukku: Quotations, purchase orders, invoices and claims'),
  jsonb_build_object('title', 'Things to note', 'body',
    'Keep a professional, on-brand tone in every client-facing message. When in doubt about wording, check with your direct manager before sending.' || chr(10) ||
    'All work lives on Google Drive, never only on your device. Save into the correct client and project folders and follow the file-naming format.' || chr(10) ||
    'Never paste confidential client data or sign-in details into public AI tools, and review every AI output before it reaches a client.'),
  jsonb_build_object('title', 'Your first day', 'body',
    '10:00am: Arrive, settle in and a quick office tour' || chr(10) || '11:30am: Set up your workstation and essential apps' || chr(10) ||
    '1:00pm: Lunch with the team' || chr(10) || '2:00pm: The Drive workspace and the accounts you will support' || chr(10) ||
    '3:00pm: Project briefings'),
  jsonb_build_object('title', 'Your first weeks', 'body',
    'Week 1: Project onboarding and our workflows; shadow live projects' || chr(10) ||
    'Weeks 2 to 4: Take ownership of assigned deliverables and learn our brand standards' || chr(10) ||
    'Months 1 to 3: Your probation, with weekly check-ins and a confirmation review'),
  jsonb_build_object('title', 'Key policies', 'body',
    'Payday: By the 7th of the following month' || chr(10) || 'Work days: Monday to Friday; Saturday and Sunday on demand' || chr(10) ||
    'Working hours: 10:00am to 7:00pm, flexible, with a one-hour lunch' || chr(10) ||
    'Leave, claims and conduct: The Employee Handbook and the guidelines in AutoCount HRMS'))
where not exists (select 1 from public.welcome_kit);

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
    'may', public.ops_granted('team.hiring', 'work'),
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
    when raise_exception then return jsonb_build_object('error', 'refused', 'reason', sqlerrm);
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

/* The Welcome Kit's words: Business settings. */
create or replace function public.welcome_kit_get()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare k public.welcome_kit;
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into k from public.welcome_kit where id = 1;
  return jsonb_build_object('ok', true, 'sections', coalesce(k.sections, '[]'::jsonb), 'updated_at', k.updated_at);
end $$;
revoke all on function public.welcome_kit_get() from public, anon;
grant execute on function public.welcome_kit_get() to authenticated;

create or replace function public.welcome_kit_save(p_sections jsonb, p_expected timestamptz)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  k public.welcome_kit;
  s jsonb;
  v_out jsonb := '[]'::jsonb;
  v_t text; v_b text;
  i int := 0;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if jsonb_typeof(p_sections) <> 'array' or jsonb_array_length(p_sections) not between 1 and 12 then
    return jsonb_build_object('error', 'bad-count');
  end if;
  for s in select * from jsonb_array_elements(p_sections) loop
    i := i + 1;
    v_t := btrim(coalesce(s->>'title', ''));
    v_b := btrim(coalesce(s->>'body', ''));
    if char_length(v_t) not between 2 and 60 then return jsonb_build_object('error', 'bad-title', 'at', i); end if;
    if char_length(v_b) not between 1 and 3000 then return jsonb_build_object('error', 'bad-body', 'at', i); end if;
    /* Never a password or a PIN in the kit (HR-SPEC: "check with your DM"). */
    if v_b ~* '(password|passcode|\mpin\M)[^\n]*:' then return jsonb_build_object('error', 'secret', 'at', i); end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('title', v_t, 'body', v_b));
  end loop;
  select * into k from public.welcome_kit where id = 1 for update;
  if k.id is null then
    insert into public.welcome_kit (id, sections, updated_by) values (1, v_out, me.id) returning * into k;
  else
    if p_expected is not null and k.updated_at <> p_expected then
      return jsonb_build_object('error', 'stale', 'sections', k.sections, 'updated_at', k.updated_at);
    end if;
    if k.sections = v_out then return jsonb_build_object('ok', true, 'same', true, 'sections', k.sections, 'updated_at', k.updated_at); end if;
    update public.welcome_kit set sections = v_out, updated_at = now(), updated_by = me.id where id = 1 returning * into k;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Welcome Kit', 'Sections: ' || (select string_agg(x->>'title', ', ') from jsonb_array_elements(v_out) x));
  return jsonb_build_object('ok', true, 'sections', k.sections, 'updated_at', k.updated_at);
end $$;
revoke all on function public.welcome_kit_save(jsonb, timestamptz) from public, anon;
grant execute on function public.welcome_kit_save(jsonb, timestamptz) to authenticated;

/* The signed-in colleague's own kit while it waits on them: the personal
   facts from their record, the team's words. Never a password or a PIN. */
create or replace function public.welcome_kit_mine()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  w public.team_welcome;
  dm public.team_members;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into w from public.team_welcome where member_id = me.id;
  if w.member_id is null or w.acked_at is not null then return jsonb_build_object('ok', true, 'due', false); end if;
  select * into dm from public.team_members where id = w.dm_id;
  return jsonb_build_object('ok', true, 'due', true, 'kit', jsonb_strip_nulls(jsonb_build_object(
    'name', me.name, 'first_day', w.first_day, 'staff_code', me.staff_code,
    'department', (select d.name from public.departments d where d.key = me.department),
    'designation', me.designation, 'email', me.email,
    'dm', case when dm.id is not null then jsonb_strip_nulls(jsonb_build_object('name', dm.name, 'mobile', dm.mobile)) end,
    'sections', (select k.sections from public.welcome_kit k where k.id = 1))));
end $$;
revoke all on function public.welcome_kit_mine() from public, anon;
grant execute on function public.welcome_kit_mine() to authenticated;

create or replace function public.welcome_kit_ack()
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); n int;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  update public.team_welcome set acked_at = now() where member_id = me.id and acked_at is null;
  get diagnostics n = row_count;
  if n > 0 then
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.edited', me.name, 'Welcome Kit acknowledged');
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.welcome_kit_ack() from public, anon;
grant execute on function public.welcome_kit_ack() to authenticated;

/* The colleague's onboarding: what the portal already knows (ticked by
   itself), the manual ticks, the assets, and the internal entry and exit
   steps. The Hiring or Personnel part. */
create or replace function public.onboarding_may()
returns boolean language sql stable security definer set search_path = public as $$
  select public.ops_granted('team.personnel', 'work') or public.ops_granted('team.hiring', 'work')
$$;
revoke all on function public.onboarding_may() from public, anon, authenticated;

create or replace function public.onboarding_get(p_member uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  t public.team_members;
  o public.team_onboarding;
  r public.personnel_records;
  w public.team_welcome;
  c public.hiring_candidates;
begin
  if not public.onboarding_may() then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.team_members where id = p_member;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into o from public.team_onboarding where member_id = p_member;
  select * into r from public.personnel_records where team_member_id = p_member;
  select * into w from public.team_welcome where member_id = p_member;
  select * into c from public.hiring_candidates where member_id = p_member order by hired_at desc limit 1;
  return jsonb_build_object('ok', true, 'updated_at', o.updated_at,
    'ticks', coalesce(o.ticks, '{}'::jsonb), 'assets', coalesce(o.assets, '[]'::jsonb),
    'known', jsonb_strip_nulls(jsonb_build_object(
      'offer', (select min(d.confirmed_at) from public.hiring_docs d where c.id is not null and d.candidate_id = c.id and d.kind = 'offer' and d.state = 'confirmed'),
      'contract', (select min(d.confirmed_at) from public.hiring_docs d where c.id is not null and d.candidate_id = c.id and d.kind = 'contract' and d.state = 'confirmed'),
      'record', r.declared_at,
      'nric', case when r.files ? 'nric_front' and r.files ? 'nric_back'
                   then greatest((r.files->'nric_front'->>'at')::timestamptz, (r.files->'nric_back'->>'at')::timestamptz) end,
      'welcome', w.acked_at, 'welcome_due', w.member_id is not null and w.acked_at is null,
      'handbook_total', (select count(*) from public.handbook_docs d where d.required and d.archived_at is null
                          and (d.current_version > 0 or d.link_url is not null)),
      'handbook_done', (select count(*) from public.handbook_docs d join public.handbook_reads h
                          on h.doc_id = d.id and h.member_id = p_member and h.version_no = d.current_version and h.acked_at is not null
                         where d.required and d.archived_at is null and (d.current_version > 0 or d.link_url is not null)))));
end $$;
revoke all on function public.onboarding_get(uuid) from public, anon;
grant execute on function public.onboarding_get(uuid) to authenticated;

/* A tick on or off: the manual checklist items (`doc`) and the internal
   entry and exit steps; each keeps who and when. */
create or replace function public.onboarding_tick(p_member uuid, p_side text, p_key text, p_on boolean)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  t public.team_members;
  o public.team_onboarding;
  k text := coalesce(p_side, '') || ':' || coalesce(p_key, '');
  v_label text;
begin
  if me.id is null or not public.onboarding_may() then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.team_members where id = p_member;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_label := case
    when p_side = 'doc' then case p_key when 'nda' then 'Non-Disclosure Agreement' when 'tp' then 'TP1 / TP2 / TP3'
      when 'entryexit' then 'Entry/Exit Form signed' end
    when p_side in ('entry', 'exit') then case p_key when 'email' then 'Work email' when 'systems' then 'AC / Bukku / Digital Portal'
      when 'files' then 'Work files access' when 'cp22' then 'CP22 / CP22A' when 'tp3' then 'TP3 / PCB release'
      when 'device' then 'Device setup / cleanup' when 'desk' then 'Desk setup / cleanup' end end;
  if v_label is null then return jsonb_build_object('error', 'bad-request'); end if;
  insert into public.team_onboarding (member_id) values (p_member) on conflict (member_id) do nothing;
  select * into o from public.team_onboarding where member_id = p_member for update;
  if coalesce(p_on, false) = (o.ticks ? k) then return jsonb_build_object('ok', true, 'same', true, 'ticks', o.ticks, 'updated_at', o.updated_at); end if;
  update public.team_onboarding
     set ticks = case when p_on then ticks || jsonb_build_object(k, jsonb_build_object('at', now(), 'by', me.name)) else ticks - k end,
         updated_at = now()
   where member_id = p_member returning * into o;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.edited', t.name, 'Onboarding: ' || v_label
    || case p_side when 'entry' then ' (entry)' when 'exit' then ' (exit)' else '' end || case when p_on then ' ticked' else ' unticked' end);
  return jsonb_build_object('ok', true, 'ticks', o.ticks, 'updated_at', o.updated_at);
end $$;
revoke all on function public.onboarding_tick(uuid, text, text, boolean) from public, anon;
grant execute on function public.onboarding_tick(uuid, text, text, boolean) to authenticated;

/* The assets issued and returned, written whole over the list as read. */
create or replace function public.onboarding_assets_save(p_member uuid, p_assets jsonb, p_expected timestamptz)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  t public.team_members;
  o public.team_onboarding;
  a jsonb;
  v_out jsonb := '[]'::jsonb;
  v_iss date; v_ret date;
  i int := 0;
begin
  if me.id is null or not public.onboarding_may() then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.team_members where id = p_member;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if jsonb_typeof(p_assets) <> 'array' or jsonb_array_length(p_assets) > 40 then return jsonb_build_object('error', 'bad-count'); end if;
  for a in select * from jsonb_array_elements(p_assets) loop
    i := i + 1;
    if coalesce(a->>'kind', '') not in ('access_card', 'key', 'device', 'namecard', 'folder', 'other') then
      return jsonb_build_object('error', 'bad-kind', 'at', i);
    end if;
    if char_length(btrim(coalesce(a->>'detail', ''))) not between 1 and 200 then return jsonb_build_object('error', 'bad-detail', 'at', i); end if;
    begin
      v_iss := nullif(a->>'issued', '')::date;
      v_ret := nullif(a->>'returned', '')::date;
    exception when others then return jsonb_build_object('error', 'bad-date', 'at', i);
    end;
    if v_iss is null or v_iss < date '2023-08-14' or v_iss > date '2099-12-31' then return jsonb_build_object('error', 'bad-date', 'at', i); end if;
    if v_ret is not null and (v_ret < v_iss or v_ret > date '2099-12-31') then return jsonb_build_object('error', 'bad-returned', 'at', i); end if;
    v_out := v_out || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('kind', a->>'kind', 'detail', btrim(a->>'detail'),
      'issued', v_iss, 'returned', v_ret)));
  end loop;
  insert into public.team_onboarding (member_id) values (p_member) on conflict (member_id) do nothing;
  select * into o from public.team_onboarding where member_id = p_member for update;
  if p_expected is not null and o.updated_at <> p_expected then
    return jsonb_build_object('error', 'stale', 'assets', o.assets, 'ticks', o.ticks, 'updated_at', o.updated_at);
  end if;
  if o.assets = v_out then return jsonb_build_object('ok', true, 'same', true, 'assets', o.assets, 'updated_at', o.updated_at); end if;
  update public.team_onboarding set assets = v_out, updated_at = now() where member_id = p_member returning * into o;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.edited', t.name, 'Onboarding: assets ' || jsonb_array_length(v_out)
    || ' (' || (select count(*) from jsonb_array_elements(v_out) x where x ? 'returned') || ' returned)');
  return jsonb_build_object('ok', true, 'assets', o.assets, 'updated_at', o.updated_at);
end $$;
revoke all on function public.onboarding_assets_save(uuid, jsonb, timestamptz) from public, anon;
grant execute on function public.onboarding_assets_save(uuid, jsonb, timestamptz) to authenticated;

-- END OF HIRING ONBOARDING -----------------------------------------------------

select public.functions_tidy();
