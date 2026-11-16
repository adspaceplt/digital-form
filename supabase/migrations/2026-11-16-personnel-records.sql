-- ===========================================================================
-- PERSONNEL RECORDS (2026-11-16)
-- ===========================================================================
-- WHY (the user, 2026-11-16, Hiring and People release H1; decisions 8 to 11
-- of tests/hr-templates/HR-SPEC.md): every colleague's employee record form
-- (sections A to H, the declaration, NRIC front and back, a photograph) held
-- in the portal and kept up to date by the colleague, the terms and salary
-- the team keys in, and the AutoCount HRMS import made from them.
--
-- WHAT CHANGED
--   * `team.personnel`, a granted part (an admin tool, Manage alone; an
--     admin's by itself, any other group's once an admin sets it):
--     `team_roles_admin_guard` holds it with the other granted parts
--     (2026-11-16-personnel-records-editor.sql, the SQL Editor's: the
--     guard's body names a removal, which the connector holds back).
--   * `personnel_records` (a colleague's form as `data`, its files' keys,
--     the consent and declaration, the employment terms) and
--     `personnel_salaries` (the probation and confirmed salary, apart) and
--     `personnel_settings` (the AutoCount company defaults): RLS on, no
--     policy, no grant. Every read and write goes through a function.
--   * The form's fields are one list (`personnel_fields()`, the page's
--     FIELDS): no field outside it is kept, each held to its kind, its length
--     and its list (AutoCount's lists: Gender, Marital Status, Race, Religion,
--     State; no "Other").
--   * `personnel_get` / `personnel_save` / `personnel_terms_set` /
--     `personnel_request` / `personnel_file_*` at `team.personnel` Work; the
--     colleague's own through `personnel_mine` / `personnel_save_mine` /
--     `personnel_file_*` with no member, behind `perf_mine_gate()`; the
--     declaration asks the consent tick and a typed name.
--   * The salary is read and written only through `personnel_salary_get` /
--     `personnel_salary_set` and the export `personnel_export`, each asking
--     `team.personnel` Work and the master-code unlock (`personnel_check`,
--     the Performance pattern; `personnel_unlock` unlocks for a holder of
--     the part as `perf_unlock` does for Performance). Never in a list, a
--     notice, the Activity record or search: a change is filed as "Salary
--     changed", never its figure.
--   * The Activity record names the fields changed, never their values.
--   * `departments.ac_code` (seeded CRE, MKT, MGT), set by
--     `department_ac_code_set`; `departments_list` answers it.
--   * `personnel_settings_get` / `personnel_settings_set` (team.settings).
--   * On a colleague's Confirm Date (join date plus probation months, MYT)
--     every active admin is told, masked ("A probation review is due. Sign
--     in to view."), once (pg_cron `personnel-probation`, 08:25 MYT).
--   * A colleague's details erased (`erased_at`) empties their record and
--     salary (trigger `team_members_erased_personnel`).
--
-- ORDER: this file (connector), its SQL Editor part, then sign-upload and
-- sign-download, then the pages. An open page before calls none of these. Safe to run twice.
--
-- ROLLBACK: departments_list and team_roles_admin_guard from their bands
-- before; the new tables and functions are left unused.
-- ===========================================================================

-- PERSONNEL RECORDS ---------------------------------------------------------

alter table public.departments add column if not exists ac_code text;
update public.departments set ac_code = 'CRE' where key = 'creative' and ac_code is null;
update public.departments set ac_code = 'MKT' where key = 'marketing' and ac_code is null;
update public.departments set ac_code = 'MGT' where key = 'management' and ac_code is null;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'departments_ac_code_check') then
    alter table public.departments add constraint departments_ac_code_check check (ac_code ~ '^[A-Z0-9]{2,10}$');
  end if;
end $$;
create unique index if not exists departments_ac_code_idx on public.departments (ac_code) where ac_code is not null;

create table if not exists public.personnel_records (
  team_member_id   uuid primary key references public.team_members(id),
  data             jsonb not null default '{}'::jsonb,
  files            jsonb not null default '{}'::jsonb,
  consent_at       timestamptz,
  declared_name    text,
  declared_at      timestamptz,
  requested_at     timestamptz,
  requested_by     uuid,
  join_date        date,
  employee_status  text check (employee_status in ('Management of the organization', 'Permanent', 'Contract', 'Part time', 'Interns', 'Others')),
  employee_type    text check (employee_type in ('FT', 'PT', 'CT')),
  probation_months integer check (probation_months between 0 and 12),
  contract_end     date,
  superior_id      uuid,
  probation_told_at timestamptz,
  updated_at       timestamptz not null default now(),
  updated_by       uuid
);
alter table public.personnel_records enable row level security;
revoke all on table public.personnel_records from public, anon, authenticated;

create table if not exists public.personnel_salaries (
  team_member_id uuid primary key references public.team_members(id),
  probation      numeric(12, 2) check (probation >= 0),
  confirmed      numeric(12, 2) check (confirmed >= 0),
  updated_at     timestamptz not null default now(),
  updated_by     uuid
);
alter table public.personnel_salaries enable row level security;
revoke all on table public.personnel_salaries from public, anon, authenticated;

create table if not exists public.personnel_settings (
  key        text primary key,
  value      text not null,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
alter table public.personnel_settings enable row level security;
revoke all on table public.personnel_settings from public, anon, authenticated;

/* The AutoCount company defaults, seeded once a key: the team changes them
   in Settings, Portal: AutoCount HRMS. */
insert into public.personnel_settings (key, value) values
  ('payment_by', 'Bank Transfer'), ('wages_type', 'Monthly'), ('pay_frequency', 'Monthly'),
  ('epf_code', '11% & 13%'), ('socso_category', 'Employment Injury Scheme and Invalidity (Category 1)'),
  ('tax_status', 'Resident'), ('socso_status', 'New Employee'), ('entitlement_group', 'STANDARD'),
  ('calendar', 'DEFAULT'), ('branch', 'JHB'), ('eclaim', '1'), ('eleave', '1'),
  ('pay_eis', '1'), ('pay_hrdf', '0'), ('epf_borne', '0'), ('socso_borne', '0'), ('eis_borne', '0'),
  ('tax_by_employer', '0'), ('socso_eis_relief', '1'), ('skbbk_exempted', '0')
on conflict (key) do nothing;

/* What each setting may hold. */
create or replace function public.personnel_setting_spec()
returns jsonb
language sql immutable set search_path = public as $$
  select '{"payment_by":"Bank Transfer|Cash|Cheque","wages_type":"Monthly|Daily|Hourly|Piece Rate",
    "pay_frequency":"Monthly|Fortnightly",
    "epf_code":"5.5% & 6.5%|9% & RM5|11% & RM5|9% & 13%|5.5% & RM5|0% & 4%|11% & 13%",
    "socso_category":"Employment Injury Scheme and Invalidity (Category 1)|Employment Injury Scheme (Category 2)",
    "tax_status":"Resident|Non-Resident|Return Expert Program|Knowledge Worker (Iskandar)|Position of C Suite",
    "socso_status":"New Employee|Resigned|Pass Away|On SOCSO Medical Leave|On No-paid Leave",
    "entitlement_group":"*","calendar":"*","branch":"*","eclaim":"0|1","eleave":"0|1","pay_eis":"0|1","pay_hrdf":"0|1",
    "epf_borne":"0|1","socso_borne":"0|1","eis_borne":"0|1","tax_by_employer":"0|1","socso_eis_relief":"0|1",
    "skbbk_exempted":"0|1"}'::jsonb
$$;
revoke all on function public.personnel_setting_spec() from public, anon, authenticated;

/* The employee record form's fields, the page's FIELDS (js/personnel.js):
   each key's kind (t:n words of n characters at most, d a date, y a year,
   mo a month, e an answer of its list, m several of it, b yes or no, i a
   whole number in its range), its label and whether the colleague's own
   declaration needs it. */
create or replace function public.personnel_fields()
returns jsonb
language sql immutable set search_path = public as $$
  select '{"full_name":["t:100","Full Name as per NRIC",1],"other_name":["t:60","Other name or Chinese name",0],"gender":["e:Male|Female","Gender",1],"birth_date":["d","Date of birth",1],"nationality":["t:60","Nationality",1],"nric":["t:20","NRIC Number",0],"old_ic":["t:15","Old IC Number",0],"passport":["t:20","Passport Number",0],"passport_expiry":["d","Passport expiry date",0],"immigration_no":["t:25","Immigration Number",0],"permit_expiry":["d","Working Permit expiry date",0],"race":["e:Malay|Chinese|Indian","Race",0],"religion":["e:Islam|Buddhist|Hindu|Christian","Religion",0],"disabled":["b","Person with disability",0],"address1":["t:120","Address line 1",1],"address2":["t:120","Address line 2",0],"postcode":["t:10","Postal code",1],"city":["t:50","City",1],"state":["e:Johor|Kedah|Kelantan|Malacca|Negeri Sembilan|Others|Pahang|Penang|Perak|Perlis|Sabah|Sarawak|Selangor|Terengganu|Wilayah Persekutuan Kuala Lumpur|Wilayah Persekutuan Labuan|Wilayah Persekutuan Putrajaya","State",1],"country":["t:60","Country",1],"email":["t:120","Email",1],"mobile":["t:25","Mobile or WhatsApp",1],"marital":["e:Single|Married|Divorced|Widowed","Marital status",1],"spouse_name":["t:60","Spouse name",0],"spouse_working":["b","Spouse working",0],"spouse_ic":["t:20","Spouse NRIC Number",0],"spouse_tax":["t:20","Spouse Income Tax Number",0],"spouse_phone":["t:25","Spouse mobile",0],"spouse_disabled":["b","Spouse with disability",0],"children_relief":["i:0:30","Children claimed for tax relief",0],"kin_name":["t:60","Name as per NRIC",1],"kin_relation":["e:Spouse|Child|Parent|Sibling","Relationship",1],"kin_mobile":["t:25","Mobile or WhatsApp",1],"kin_address1":["t:120","Address line 1",0],"kin_address2":["t:120","Address line 2",0],"kin_postcode":["t:10","Postal code",0],"kin_city":["t:50","City",0],"kin_state":["t:50","State",0],"kin_country":["t:60","Country",0],"bank":["t:150","Bank",1],"bank_account":["t:30","Account number",1],"bank_holder":["t:60","Account holder name",1],"epf_no":["t:20","EPF Number",0],"socso_no":["t:12","SOCSO Number",0],"tax_no":["t:20","Income Tax Number",0],"edu_primary_school":["t:100","Primary: school",0],"edu_primary_from":["y","Primary: from",0],"edu_primary_to":["y","Primary: to",0],"edu_primary_qual":["t:100","Primary: highest qualification",0],"edu_primary_results":["t:60","Primary: results",0],"edu_secondary_school":["t:100","Secondary: school",0],"edu_secondary_from":["y","Secondary: from",0],"edu_secondary_to":["y","Secondary: to",0],"edu_secondary_qual":["t:100","Secondary: highest qualification",0],"edu_secondary_results":["t:60","Secondary: results",0],"edu_college_school":["t:100","College or Pre-U: school",0],"edu_college_from":["y","College or Pre-U: from",0],"edu_college_to":["y","College or Pre-U: to",0],"edu_college_qual":["t:100","College or Pre-U: highest qualification",0],"edu_college_results":["t:60","College or Pre-U: results",0],"edu_university_school":["t:100","University: school",0],"edu_university_from":["y","University: from",0],"edu_university_to":["y","University: to",0],"edu_university_qual":["t:100","University: highest qualification",0],"edu_university_results":["t:60","University: results",0],"edu_professional_school":["t:100","Professional: school",0],"edu_professional_from":["y","Professional: from",0],"edu_professional_to":["y","Professional: to",0],"edu_professional_qual":["t:100","Professional: highest qualification",0],"edu_professional_results":["t:60","Professional: results",0],"training_1_course":["t:100","Training 1: type of course",0],"training_1_institution":["t:100","Training 1: institution",0],"training_1_qual":["t:100","Training 1: qualification",0],"training_1_year":["y","Training 1: year",0],"training_2_course":["t:100","Training 2: type of course",0],"training_2_institution":["t:100","Training 2: institution",0],"training_2_qual":["t:100","Training 2: qualification",0],"training_2_year":["y","Training 2: year",0],"training_3_course":["t:100","Training 3: type of course",0],"training_3_institution":["t:100","Training 3: institution",0],"training_3_qual":["t:100","Training 3: qualification",0],"training_3_year":["y","Training 3: year",0],"lang_en_spoken":["e:Excellent|Good|Fair|Poor","English: spoken",0],"lang_en_written":["e:Excellent|Good|Fair|Poor","English: written",0],"lang_zh_spoken":["e:Excellent|Good|Fair|Poor","Chinese: spoken",0],"lang_zh_written":["e:Excellent|Good|Fair|Poor","Chinese: written",0],"lang_ms_spoken":["e:Excellent|Good|Fair|Poor","Malay: spoken",0],"lang_ms_written":["e:Excellent|Good|Fair|Poor","Malay: written",0],"lang_other":["t:30","Other language",0],"lang_other_spoken":["e:Excellent|Good|Fair|Poor","Other language: spoken",0],"lang_other_written":["e:Excellent|Good|Fair|Poor","Other language: written",0],"typing":["e:Fast|Normal|Slow","Typing",0],"software":["m:Word|Excel|PowerPoint|Outlook","Software",0],"other_skills":["t:300","Other skills",0],"job_1_company":["t:100","Employment 1: company",0],"job_1_nature":["t:100","Employment 1: nature of business",0],"job_1_location":["t:60","Employment 1: location",0],"job_1_position":["t:60","Employment 1: position",0],"job_1_from":["mo","Employment 1: from",0],"job_1_to":["mo","Employment 1: to",0],"job_1_notes":["t:500","Employment 1: notes and reason for leaving",0],"job_2_company":["t:100","Employment 2: company",0],"job_2_nature":["t:100","Employment 2: nature of business",0],"job_2_location":["t:60","Employment 2: location",0],"job_2_position":["t:60","Employment 2: position",0],"job_2_from":["mo","Employment 2: from",0],"job_2_to":["mo","Employment 2: to",0],"job_2_notes":["t:500","Employment 2: notes and reason for leaving",0],"job_3_company":["t:100","Employment 3: company",0],"job_3_nature":["t:100","Employment 3: nature of business",0],"job_3_location":["t:60","Employment 3: location",0],"job_3_position":["t:60","Employment 3: position",0],"job_3_from":["mo","Employment 3: from",0],"job_3_to":["mo","Employment 3: to",0],"job_3_notes":["t:500","Employment 3: notes and reason for leaving",0],"heard":["e:Newspaper ads|Friends or relatives|Websites|Career fair","How they learned about ADspace",0],"applied_before":["b","Applied to ADspace before",0],"relative":["b","Relative or friend at ADspace",0],"relative_name":["t:100","Relative or friend: name and relationship",0],"convicted":["b","Convicted of a criminal offence",0],"conviction_note":["t:500","Conviction details",0],"licence":["b","Driving licence",0],"transport":["t:60","Transport to work",0],"ref_1_name":["t:60","Reference 1: name",0],"ref_1_title":["t:60","Reference 1: title",0],"ref_1_company":["t:100","Reference 1: company",0],"ref_1_address":["t:150","Reference 1: short address",0],"ref_1_phone":["t:25","Reference 1: contact number",0],"ref_2_name":["t:60","Reference 2: name",0],"ref_2_title":["t:60","Reference 2: title",0],"ref_2_company":["t:100","Reference 2: company",0],"ref_2_address":["t:150","Reference 2: short address",0],"ref_2_phone":["t:25","Reference 2: contact number",0]}'::jsonb
$$;
revoke all on function public.personnel_fields() from public, anon, authenticated;

/* A form's answers held to their fields: the cleaned answers, else the
   first field refused. An empty answer is left out. */
create or replace function public.personnel_clean(p_data jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  f jsonb := public.personnel_fields();
  k text; v jsonb; spec jsonb; kind text; s text; parts text[]; out jsonb := '{}'::jsonb; x jsonb; n numeric;
begin
  if p_data is null or jsonb_typeof(p_data) <> 'object' then return jsonb_build_object('error', 'bad-field', 'field', null); end if;
  for k, v in select key, value from jsonb_each(p_data) loop
    spec := f -> k;
    if spec is null then return jsonb_build_object('error', 'bad-field', 'field', k); end if;
    if v is null or v = 'null'::jsonb or v = '""'::jsonb or v = '[]'::jsonb then continue; end if;
    kind := spec ->> 0;
    parts := string_to_array(kind, ':');
    if parts[1] = 'b' then
      if jsonb_typeof(v) <> 'boolean' then return jsonb_build_object('error', 'bad-field', 'field', k); end if;
      out := out || jsonb_build_object(k, v);
      continue;
    end if;
    if parts[1] = 'i' then
      if jsonb_typeof(v) <> 'number' then return jsonb_build_object('error', 'bad-field', 'field', k); end if;
      n := v::text::numeric;
      if n <> trunc(n) or n < parts[2]::numeric or n > parts[3]::numeric then
        return jsonb_build_object('error', 'bad-field', 'field', k);
      end if;
      out := out || jsonb_build_object(k, n::int);
      continue;
    end if;
    if parts[1] = 'm' then
      if jsonb_typeof(v) <> 'array' then return jsonb_build_object('error', 'bad-field', 'field', k); end if;
      for x in select value from jsonb_array_elements(v) loop
        if jsonb_typeof(x) <> 'string' or not (x #>> '{}' = any (string_to_array(substr(kind, 3), '|'))) then
          return jsonb_build_object('error', 'bad-field', 'field', k);
        end if;
      end loop;
      out := out || jsonb_build_object(k, (select jsonb_agg(distinct e) from jsonb_array_elements_text(v) e));
      continue;
    end if;
    if jsonb_typeof(v) <> 'string' then return jsonb_build_object('error', 'bad-field', 'field', k); end if;
    s := btrim(regexp_replace(v #>> '{}', '[\r\n\t]+', ' ', 'g'));
    if s = '' then continue; end if;
    if parts[1] = 't' then
      if char_length(s) > parts[2]::int or s ~ '[<>]' then return jsonb_build_object('error', 'bad-field', 'field', k); end if;
    elsif parts[1] = 'e' then
      if not (s = any (string_to_array(substr(kind, 3), '|'))) then return jsonb_build_object('error', 'bad-field', 'field', k); end if;
    elsif parts[1] = 'd' then
      if s !~ '^(19|20)[0-9]{2}-[0-9]{2}-[0-9]{2}$' or to_char(to_date(s, 'YYYY-MM-DD'), 'YYYY-MM-DD') <> s then
        return jsonb_build_object('error', 'bad-field', 'field', k);
      end if;
    elsif parts[1] = 'y' then
      if s !~ '^(19|20)[0-9]{2}$' then return jsonb_build_object('error', 'bad-field', 'field', k); end if;
    elsif parts[1] = 'mo' then
      if s !~ '^(19|20)[0-9]{2}-(0[1-9]|1[0-2])$' then return jsonb_build_object('error', 'bad-field', 'field', k); end if;
    else
      return jsonb_build_object('error', 'bad-field', 'field', k);
    end if;
    out := out || jsonb_build_object(k, s);
  end loop;
  return jsonb_build_object('ok', true, 'data', out);
end $$;
revoke all on function public.personnel_clean(jsonb) from public, anon, authenticated;

/* What the declaration still needs: the required fields, an NRIC or a
   passport, the spouse's name once married. */
create or replace function public.personnel_missing(p_data jsonb)
returns text[]
language sql immutable set search_path = public as $$
  select coalesce(array(select k from jsonb_each(public.personnel_fields()) f(k, spec)
                          where (spec ->> 2) = '1' and coalesce(p_data ->> k, '') = '' order by k), '{}')
    || case when coalesce(p_data ->> 'nric', '') = '' and coalesce(p_data ->> 'passport', '') = '' then array['nric'] else '{}'::text[] end
    || case when p_data ->> 'marital' = 'Married' and coalesce(p_data ->> 'spouse_name', '') = '' then array['spouse_name'] else '{}'::text[] end
$$;
revoke all on function public.personnel_missing(jsonb) from public, anon, authenticated;

/* The labels of the fields that differ, for the Activity record: never a value. */
create or replace function public.personnel_changed(p_old jsonb, p_new jsonb)
returns text
language sql immutable set search_path = public as $$
  select string_agg(f.spec ->> 1, ', ' order by f.k)
    from jsonb_each(public.personnel_fields()) f(k, spec)
   where (coalesce(p_old, '{}'::jsonb) -> f.k) is distinct from (coalesce(p_new, '{}'::jsonb) -> f.k)
$$;
revoke all on function public.personnel_changed(jsonb, jsonb) from public, anon, authenticated;

/* The day a probation ends (MYT): the join date plus its months. */
create or replace function public.personnel_confirm_date(p_join date, p_months integer)
returns date
language sql immutable set search_path = public as $$
  select case when p_join is null or p_months is null then null else (p_join + make_interval(months => p_months))::date end
$$;
revoke all on function public.personnel_confirm_date(date, integer) from public, anon, authenticated;

create or replace function public.personnel_today()
returns date
language sql stable set search_path = public as $$
  select (now() at time zone 'Asia/Kuala_Lumpur')::date
$$;
revoke all on function public.personnel_today() from public, anon, authenticated;

/* The fresh proof for the salary and the export: the Performance unlock,
   for a holder of the part (2026-11-16, decision 10). */
create or replace function public.personnel_check(p_token text)
returns text
language plpgsql security definer set search_path = public as $$
declare m public.team_members; n integer;
begin
  m := public.ops_me();
  if m.id is null then return 'not-team'; end if;
  if not public.ops_granted('team.personnel', 'work') then return 'denied'; end if;
  if not public.perf_code_set() then return 'no-code'; end if;
  update public.perf_unlocks set expires_at = now() + interval '15 minutes'
   where token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex')
     and team_member_id = m.id and expires_at > now();
  get diagnostics n = row_count;
  if n = 0 then return 'code-needed'; end if;
  return null;
end $$;
revoke all on function public.personnel_check(text) from public, anon, authenticated;

/* The master code for a holder of Personnel, counted and locked as
   `perf_unlock` counts it; the token it answers is the same unlock. */
create or replace function public.personnel_unlock(p_code text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  m public.team_members; h text; a public.perf_attempts; tok text; f integer;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_granted('team.personnel', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select value into h from public.app_secrets where key = 'perf_code';
  if coalesce(h, '') = '' then return jsonb_build_object('error', 'no-code'); end if;
  insert into public.perf_attempts (team_member_id, failures) values (m.id, 0)
  on conflict (team_member_id) do nothing;
  select * into a from public.perf_attempts where team_member_id = m.id for update;
  if a.locked_until > now() then
    return jsonb_build_object('error', 'locked', 'until', a.locked_until);
  end if;
  if crypt(coalesce(p_code, ''), h) <> h then
    f := case when a.locked_until is not null then 1 else coalesce(a.failures, 0) + 1 end;
    update public.perf_attempts set failures = f,
           locked_until = case when f >= 5 then now() + interval '15 minutes' end
     where team_member_id = m.id;
    perform public.perf_log(null, null, 'unlock_failed', jsonb_build_object('failures', f));
    if f >= 5 then
      return jsonb_build_object('error', 'locked', 'until', now() + interval '15 minutes');
    end if;
    return jsonb_build_object('error', 'wrong-code', 'left', 5 - f);
  end if;
  update public.perf_attempts set failures = 0, locked_until = null where team_member_id = m.id;
  tok := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  insert into public.perf_unlocks (token_hash, team_member_id, expires_at)
  values (encode(sha256(convert_to(tok, 'UTF8')), 'hex'), m.id, now() + interval '15 minutes');
  perform public.perf_log(null, null, 'unlocked', '{}'::jsonb);
  return jsonb_build_object('token', tok, 'expires_at', now() + interval '15 minutes');
end $$;
revoke all on function public.personnel_unlock(text) from public, anon;
grant execute on function public.personnel_unlock(text) to authenticated;

/* One record as the reader may read it: never a salary, never a file's key. */
create or replace function public.personnel_json(p_member uuid, p_team boolean)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.personnel_records; t public.team_members; s public.personnel_salaries;
begin
  select * into t from public.team_members where id = p_member;
  select * into r from public.personnel_records where team_member_id = p_member;
  select * into s from public.personnel_salaries where team_member_id = p_member;
  return jsonb_build_object('ok', true, 'member', p_member, 'name', t.name,
    'data', coalesce(r.data, '{}'::jsonb),
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
revoke all on function public.personnel_json(uuid, boolean) from public, anon, authenticated;

create or replace function public.personnel_get(p_member uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.ops_granted('team.personnel', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not exists (select 1 from public.team_members t where t.id = p_member) then return jsonb_build_object('error', 'not-found'); end if;
  return public.personnel_json(p_member, true);
end $$;
revoke all on function public.personnel_get(uuid) from public, anon;
grant execute on function public.personnel_get(uuid) to authenticated;

create or replace function public.personnel_mine()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare g jsonb;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  return public.personnel_json((public.ops_me()).id, false);
end $$;
revoke all on function public.personnel_mine() from public, anon;
grant execute on function public.personnel_mine() to authenticated;

/* The team's save: any field, no declaration asked. */
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
  c := public.personnel_clean(p_data);
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
  values (coalesce(me.name, 'admin'), 'team.edited', t.name, 'Personnel record: ' || what);
  return public.personnel_json(p_member, true);
end $$;
revoke all on function public.personnel_save(uuid, jsonb, timestamptz) from public, anon;
grant execute on function public.personnel_save(uuid, jsonb, timestamptz) to authenticated;

/* The colleague's own: complete, consented and declared under their name. */
create or replace function public.personnel_save_mine(p_data jsonb, p_consent boolean, p_name text, p_expected timestamptz)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare g jsonb; me public.team_members; r public.personnel_records; c jsonb; miss text[];
        v_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')); what text;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  me := public.ops_me();
  c := public.personnel_clean(p_data);
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
          'Personnel record declared' || coalesce(': ' || what, ''));
  return public.personnel_json(me.id, false);
end $$;
revoke all on function public.personnel_save_mine(jsonb, boolean, text, timestamptz) from public, anon;
grant execute on function public.personnel_save_mine(jsonb, boolean, text, timestamptz) to authenticated;

/* The employment terms the team keys in. A new join date or probation
   tells the admins again on the new Confirm Date. */
create or replace function public.personnel_terms_set(p_member uuid, p_join date, p_status text, p_type text,
  p_probation integer, p_contract_end date, p_superior uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare me public.team_members; t public.team_members; r public.personnel_records; moves text[] := '{}';
begin
  if not public.ops_granted('team.personnel', 'work') then return jsonb_build_object('error', 'denied'); end if;
  me := public.ops_me();
  select * into t from public.team_members where id = p_member;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_status is not null and p_status not in ('Management of the organization', 'Permanent', 'Contract', 'Part time', 'Interns', 'Others') then
    return jsonb_build_object('error', 'bad-status');
  end if;
  if p_type is not null and p_type not in ('FT', 'PT', 'CT') then return jsonb_build_object('error', 'bad-type'); end if;
  if p_probation is not null and (p_probation < 0 or p_probation > 12) then return jsonb_build_object('error', 'bad-probation'); end if;
  if p_join is not null and (p_join < date '2023-08-14' or p_join > date '2099-12-31') then return jsonb_build_object('error', 'bad-date'); end if;
  if p_contract_end is not null and p_join is not null and p_contract_end <= p_join then return jsonb_build_object('error', 'bad-end'); end if;
  if p_superior is not null and (p_superior = p_member or not exists (select 1 from public.team_members s where s.id = p_superior and s.active)) then
    return jsonb_build_object('error', 'bad-superior');
  end if;
  insert into public.personnel_records (team_member_id) values (p_member) on conflict (team_member_id) do nothing;
  select * into r from public.personnel_records where team_member_id = p_member for update;
  if r.join_date is distinct from p_join then moves := moves || 'Join date'::text; end if;
  if r.employee_status is distinct from p_status then moves := moves || 'Employee status'::text; end if;
  if r.employee_type is distinct from p_type then moves := moves || 'Employee type'::text; end if;
  if r.probation_months is distinct from p_probation then moves := moves || 'Probation'::text; end if;
  if r.contract_end is distinct from p_contract_end then moves := moves || 'End of contract'::text; end if;
  if r.superior_id is distinct from p_superior then moves := moves || 'Reports to'::text; end if;
  if cardinality(moves) = 0 then return public.personnel_json(p_member, true); end if;
  update public.personnel_records set join_date = p_join, employee_status = p_status, employee_type = p_type,
         probation_months = p_probation, contract_end = p_contract_end, superior_id = p_superior,
         probation_told_at = case when r.join_date is distinct from p_join or r.probation_months is distinct from p_probation
                                  then null else r.probation_told_at end,
         updated_at = now(), updated_by = me.id
   where team_member_id = p_member;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(me.name, 'admin'), 'team.edited', t.name, 'Employment terms: ' || array_to_string(moves, ', '));
  return public.personnel_json(p_member, true);
end $$;
revoke all on function public.personnel_terms_set(uuid, date, text, text, integer, date, uuid) from public, anon;
grant execute on function public.personnel_terms_set(uuid, date, text, text, integer, date, uuid) to authenticated;

/* Request employee record: the colleague is told, once a day at most. */
create or replace function public.personnel_request(p_member uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare me public.team_members; t public.team_members;
begin
  if not public.ops_granted('team.personnel', 'work') then return jsonb_build_object('error', 'denied'); end if;
  me := public.ops_me();
  select * into t from public.team_members where id = p_member;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not t.active or coalesce(t.system, false) then return jsonb_build_object('error', 'inactive'); end if;
  if t.id = me.id then return jsonb_build_object('error', 'own'); end if;
  insert into public.personnel_records (team_member_id) values (p_member) on conflict (team_member_id) do nothing;
  update public.personnel_records set requested_at = now(), requested_by = me.id where team_member_id = p_member;
  perform public.perf_notify(p_member, 'personnel.request', 'Please complete your employee record in My records.',
    'personnel.request:' || p_member || ':' || public.personnel_today());
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(me.name, 'admin'), 'team.edited', t.name, 'Employee record requested');
  return jsonb_build_object('ok', true, 'requested_at', now());
end $$;
revoke all on function public.personnel_request(uuid) from public, anon;
grant execute on function public.personnel_request(uuid) to authenticated;

/* Whose files the caller may add, read or remove: their own behind the
   fresh proof (no member named), else anyone's at the part. Answers the
   member, else null. */
create or replace function public.personnel_file_member(p_member uuid)
returns uuid
language plpgsql stable security definer set search_path = public as $$
declare me public.team_members;
begin
  me := public.ops_me();
  if me.id is null then return null; end if;
  if p_member is null then
    if public.perf_mine_gate() is not null then return null; end if;
    return me.id;
  end if;
  if not public.ops_granted('team.personnel', 'work') then return null; end if;
  if not exists (select 1 from public.team_members t where t.id = p_member and t.erased_at is null) then return null; end if;
  return p_member;
end $$;
revoke all on function public.personnel_file_member(uuid) from public, anon;
grant execute on function public.personnel_file_member(uuid) to authenticated;

create or replace function public.personnel_file_set(p_member uuid, p_kind text, p_key text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare who uuid := public.personnel_file_member(p_member); me public.team_members; t public.team_members; ty text;
begin
  if who is null then return jsonb_build_object('error', 'denied'); end if;
  if p_kind not in ('nric_front', 'nric_back', 'photo') then return jsonb_build_object('error', 'bad-kind'); end if;
  if p_key is null or p_key !~ ('^private/personnel/' || who || '/[0-9a-f-]{36}\.(jpg|png|pdf)$') then
    return jsonb_build_object('error', 'bad-key');
  end if;
  if p_kind = 'photo' and p_key !~ '\.(jpg|png)$' then return jsonb_build_object('error', 'bad-key'); end if;
  ty := substring(p_key from '\.([a-z]+)$');
  me := public.ops_me();
  select * into t from public.team_members where id = who;
  insert into public.personnel_records (team_member_id) values (who) on conflict (team_member_id) do nothing;
  update public.personnel_records
     set files = files || jsonb_build_object(p_kind, jsonb_build_object('key', p_key, 'at', now(), 'type', ty)),
         updated_at = now(), updated_by = me.id
   where team_member_id = who;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(me.name, 'colleague'), 'team.edited', t.name, 'Personnel record: '
    || case p_kind when 'nric_front' then 'NRIC front' when 'nric_back' then 'NRIC back' else 'Photograph' end || ' added');
  return public.personnel_json(who, who <> me.id);
end $$;
revoke all on function public.personnel_file_set(uuid, text, text) from public, anon;
grant execute on function public.personnel_file_set(uuid, text, text) to authenticated;

/* A file taken off the record; the stored copy stays in S3. */
create or replace function public.personnel_file_remove(p_member uuid, p_kind text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare who uuid := public.personnel_file_member(p_member); me public.team_members; t public.team_members;
begin
  if who is null then return jsonb_build_object('error', 'denied'); end if;
  if p_kind not in ('nric_front', 'nric_back', 'photo') then return jsonb_build_object('error', 'bad-kind'); end if;
  me := public.ops_me();
  select * into t from public.team_members where id = who;
  update public.personnel_records set files = files - p_kind, updated_at = now(), updated_by = me.id
   where team_member_id = who and files ? p_kind;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(me.name, 'colleague'), 'team.edited', t.name, 'Personnel record: '
    || case p_kind when 'nric_front' then 'NRIC front' when 'nric_back' then 'NRIC back' else 'Photograph' end || ' removed');
  return public.personnel_json(who, who <> me.id);
end $$;
revoke all on function public.personnel_file_remove(uuid, text) from public, anon;
grant execute on function public.personnel_file_remove(uuid, text) to authenticated;

/* sign-download asks this as the caller to read one file back. */
create or replace function public.personnel_file_key(p_member uuid, p_kind text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare who uuid := public.personnel_file_member(p_member); k text;
begin
  if who is null then return jsonb_build_object('error', 'denied'); end if;
  select r.files -> p_kind ->> 'key' into k from public.personnel_records r where r.team_member_id = who;
  if k is null then return jsonb_build_object('error', 'not-kept'); end if;
  return jsonb_build_object('key', k, 'member', who);
end $$;
revoke all on function public.personnel_file_key(uuid, text) from public, anon;
grant execute on function public.personnel_file_key(uuid, text) to authenticated;

/* The salary, behind the part and the unlock: read for one colleague. */
create or replace function public.personnel_salary_get(p_token text, p_member uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare e text; s public.personnel_salaries;
begin
  e := public.personnel_check(p_token);
  if e is not null then return jsonb_build_object('error', e); end if;
  select * into s from public.personnel_salaries where team_member_id = p_member;
  return jsonb_build_object('ok', true, 'probation', s.probation, 'confirmed', s.confirmed, 'updated_at', s.updated_at);
end $$;
revoke all on function public.personnel_salary_get(text, uuid) from public, anon;
grant execute on function public.personnel_salary_get(text, uuid) to authenticated;

create or replace function public.personnel_salary_set(p_token text, p_member uuid, p_probation numeric, p_confirmed numeric)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare e text; me public.team_members; t public.team_members; s public.personnel_salaries;
begin
  e := public.personnel_check(p_token);
  if e is not null then return jsonb_build_object('error', e); end if;
  me := public.ops_me();
  select * into t from public.team_members where id = p_member;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if (p_probation is not null and (p_probation < 0 or p_probation >= 10000000))
     or (p_confirmed is not null and (p_confirmed < 0 or p_confirmed >= 10000000)) then
    return jsonb_build_object('error', 'bad-amount');
  end if;
  insert into public.personnel_salaries (team_member_id) values (p_member) on conflict (team_member_id) do nothing;
  select * into s from public.personnel_salaries where team_member_id = p_member for update;
  if s.probation is not distinct from round(p_probation, 2) and s.confirmed is not distinct from round(p_confirmed, 2) then
    return jsonb_build_object('ok', true, 'probation', s.probation, 'confirmed', s.confirmed, 'updated_at', s.updated_at);
  end if;
  update public.personnel_salaries set probation = round(p_probation, 2), confirmed = round(p_confirmed, 2),
         updated_at = now(), updated_by = me.id
   where team_member_id = p_member returning * into s;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(me.name, 'admin'), 'team.edited', t.name, 'Salary changed');
  return jsonb_build_object('ok', true, 'probation', s.probation, 'confirmed', s.confirmed, 'updated_at', s.updated_at);
end $$;
revoke all on function public.personnel_salary_set(text, uuid, numeric, numeric) from public, anon;
grant execute on function public.personnel_salary_set(text, uuid, numeric, numeric) to authenticated;

/* Every active colleague's record for the AutoCount import, the basic rate
   the one in force today; each read filed, never a figure. */
create or replace function public.personnel_export(p_token text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare e text; me public.team_members; rows jsonb; n integer; today date := public.personnel_today();
begin
  e := public.personnel_check(p_token);
  if e is not null then return jsonb_build_object('error', e); end if;
  me := public.ops_me();
  select coalesce(jsonb_agg(jsonb_build_object(
      'member', t.id, 'code', t.staff_code, 'name', t.name, 'designation', t.designation, 'email', t.email,
      'department', t.department, 'department_code', d.ac_code, 'active', t.active,
      'data', coalesce(r.data, '{}'::jsonb), 'join_date', r.join_date,
      'confirm_date', public.personnel_confirm_date(r.join_date, r.probation_months),
      'employee_status', r.employee_status, 'employee_type', r.employee_type, 'contract_end', r.contract_end,
      'superior_code', (select u.staff_code from public.team_members u where u.id = r.superior_id),
      'basic_rate', case
        when s.confirmed is not null and (public.personnel_confirm_date(r.join_date, r.probation_months) is null
             or public.personnel_confirm_date(r.join_date, r.probation_months) <= today) then s.confirmed
        else coalesce(s.probation, s.confirmed) end)
      order by t.staff_code nulls last, t.name), '[]'::jsonb), count(*)
    into rows, n
    from public.team_members t
    left join public.personnel_records r on r.team_member_id = t.id
    left join public.personnel_salaries s on s.team_member_id = t.id
    left join public.departments d on d.key = t.department
   where t.active and not coalesce(t.system, false) and t.removed_at is null;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(me.name, 'admin'), 'team.changed', 'AutoCount HRMS', 'Downloaded for AutoCount: ' || n || ' colleagues');
  return jsonb_build_object('ok', true, 'rows', rows,
    'settings', (select jsonb_object_agg(x.key, x.value) from public.personnel_settings x));
end $$;
revoke all on function public.personnel_export(text) from public, anon;
grant execute on function public.personnel_export(text) to authenticated;

create or replace function public.personnel_settings_get()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.ops_granted('team.settings', 'work') or public.ops_granted('team.personnel', 'work')) then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'values', (select jsonb_object_agg(x.key, x.value) from public.personnel_settings x),
    'spec', public.personnel_setting_spec());
end $$;
revoke all on function public.personnel_settings_get() from public, anon;
grant execute on function public.personnel_settings_get() to authenticated;

create or replace function public.personnel_settings_set(p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare me public.team_members; spec jsonb := public.personnel_setting_spec(); k text; v text; was text; moves text[] := '{}';
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_values is null or jsonb_typeof(p_values) <> 'object' then return jsonb_build_object('error', 'bad-value'); end if;
  me := public.ops_me();
  for k, v in select key, value from jsonb_each_text(p_values) loop
    if not spec ? k then return jsonb_build_object('error', 'bad-value', 'key', k); end if;
    v := btrim(coalesce(v, ''));
    if spec ->> k = '*' then
      if v !~ '^[A-Za-z0-9 ._-]{1,20}$' then return jsonb_build_object('error', 'bad-value', 'key', k); end if;
    elsif not (v = any (string_to_array(spec ->> k, '|'))) then
      return jsonb_build_object('error', 'bad-value', 'key', k);
    end if;
  end loop;
  for k, v in select key, btrim(value) from jsonb_each_text(p_values) loop
    select x.value into was from public.personnel_settings x where x.key = k;
    if was is distinct from v then
      insert into public.personnel_settings (key, value, updated_at, updated_by) values (k, v, now(), me.id)
      on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = me.id;
      moves := moves || (k || ': ' || coalesce(was, 'not set') || ' → ' || v);
    end if;
  end loop;
  if cardinality(moves) > 0 then
    insert into public.activity_log (actor, action, subject, detail)
    values (coalesce(me.name, 'admin'), 'team.changed', 'AutoCount HRMS', array_to_string(moves, ' · '));
  end if;
  return public.personnel_settings_get();
end $$;
revoke all on function public.personnel_settings_set(jsonb) from public, anon;
grant execute on function public.personnel_settings_set(jsonb) to authenticated;

create or replace function public.department_ac_code_set(p_key text, p_code text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare me public.team_members; d public.departments; v text := nullif(upper(btrim(coalesce(p_code, ''))), '');
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  me := public.ops_me();
  select * into d from public.departments where key = p_key for update;
  if d.key is null then return jsonb_build_object('error', 'not-found'); end if;
  if v is not null and v !~ '^[A-Z0-9]{2,10}$' then return jsonb_build_object('error', 'bad-code'); end if;
  if v is not null and exists (select 1 from public.departments x where x.ac_code = v and x.key <> p_key) then
    return jsonb_build_object('error', 'taken');
  end if;
  if d.ac_code is not distinct from v then return jsonb_build_object('ok', true); end if;
  update public.departments set ac_code = v, updated_at = now(), updated_by = me.id where key = p_key;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(me.name, 'admin'), 'team.changed', 'Departments',
          d.name || ' · AutoCount code: ' || coalesce(d.ac_code, 'not set') || ' → ' || coalesce(v, 'not set'));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.department_ac_code_set(text, text) from public, anon;
grant execute on function public.department_ac_code_set(text, text) to authenticated;

create or replace function public.departments_list()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_team() then return jsonb_build_object('error', 'denied'); end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'key', d.key, 'name', d.name, 'active', d.active, 'in_prize', d.in_prize,
      'criteria', coalesce(d.criteria, '[]'::jsonb), 'ac_code', d.ac_code,
      'members', (select count(*)::int from public.team_members t where t.department = d.key and t.active),
      'in_records', exists (select 1 from public.team_members t where t.department = d.key)
                    or exists (select 1 from public.perf_people p where p.department = d.key)
                    or exists (select 1 from public.perf_dept_scores s where s.department = d.key))
      order by d.position, lower(d.name))
    from public.departments d), '[]'::jsonb);
end $$;
revoke all on function public.departments_list() from public, anon;
grant execute on function public.departments_list() to authenticated;

/* On the Confirm Date the admins are told, masked: no name, no figure. */
create or replace function public.personnel_probation_due()
returns integer
language plpgsql security definer set search_path = public as $$
declare r record; a record; n integer := 0; today date := public.personnel_today();
begin
  for r in select p.team_member_id, public.personnel_confirm_date(p.join_date, p.probation_months) as due
             from public.personnel_records p join public.team_members t on t.id = p.team_member_id
            where t.active and p.probation_told_at is null and p.probation_months > 0
              and public.personnel_confirm_date(p.join_date, p.probation_months) between today - 7 and today
  loop
    for a in select t.id from public.team_members t
              where t.active and (t.is_admin or t.role = 'admin') and not coalesce(t.system, false) loop
      perform public.perf_notify(a.id, 'personnel.probation', 'A probation review is due. Sign in to view.',
        'personnel.probation:' || r.team_member_id || ':' || r.due || ':' || a.id);
    end loop;
    update public.personnel_records set probation_told_at = now() where team_member_id = r.team_member_id;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.personnel_probation_due() from public, anon, authenticated;

/* A colleague's details erased take their record and salary with them. */
create or replace function public.team_members_erased_personnel()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.erased_at is not null and old.erased_at is null then
    update public.personnel_records set data = '{}'::jsonb, files = '{}'::jsonb, consent_at = null,
           declared_name = null, declared_at = null, updated_at = now()
     where team_member_id = new.id;
    update public.personnel_salaries set probation = null, confirmed = null, updated_at = now()
     where team_member_id = new.id;
  end if;
  return new;
end $$;
revoke all on function public.team_members_erased_personnel() from public, anon, authenticated;
create or replace trigger team_members_erased_personnel after update of erased_at on public.team_members
  for each row execute function public.team_members_erased_personnel();

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: no probation notices go out until it is.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'personnel-probation';
  perform cron.schedule('personnel-probation', '25 0 * * *', 'select public.personnel_probation_due()');
end $$;

-- END OF PERSONNEL RECORDS --------------------------------------------------

select public.functions_tidy();
