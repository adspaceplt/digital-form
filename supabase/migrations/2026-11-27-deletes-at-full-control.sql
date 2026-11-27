-- ===========================================================================
-- DELETES AT FULL CONTROL — every delete asks Full control (2026-11-27)
-- ===========================================================================
-- WHY: only Full control deletes; at Edit a Delete is a request an admin
-- approves (the user, 2026-11-17; "go all 13", 2026-11-27). A live audit
-- found 13 delete functions an admin tool's Edit could run for good, none
-- on `delete_kinds`: `analytics_read_delete` (team.analytics),
-- `announcement_delete` (team.announce), `campaign_file_delete`
-- (campaigns.files_delete), `department_delete`, `industry_delete`,
-- `public_holiday_delete`, `tax_codes_delete` (team.settings),
-- `doc_type_delete` (register.types), `handbook_delete` (team.handbook),
-- `hiring_delete`, `hiring_scorecard_delete` (team.hiring),
-- `ops_template_delete` (ops.workflows), `team_notice_delete` (team.notice).
--
-- WHAT IT CHANGES
--   * Each of the 13 asks its grant at Full control (`ops_granted(…,
--     'manage')`), refusing `denied` below it; every other check as before.
--   * Each joins `delete_kinds`, so at Edit its Delete files a request.
--   * `delete_request_file`: a granted part is asked through `ops_granted`
--     (`allowed()` reads an unset part as its section, which a granted part
--     never takes); tax codes are requested several at once, each held and
--     named; an approved file is named by its creator and held to its
--     campaign's client.
--
-- ORDER: this migration, then the pages (each Delete at Edit reads Request
-- delete). An open tab from before draws Delete at Edit and is refused
-- `denied`, said as each screen's permission line.
--
-- ROLLBACK: run the 13 functions and `delete_request_file` as their
-- previous last definitions in schema.sql state them, and delete the 13
-- `rpc:` rows this band adds to `delete_kinds` (none while a request names
-- one: decide or withdraw it first).
-- ===========================================================================

create or replace function public.analytics_read_delete(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  a public.analytics_reads;
begin
  if not public.ops_granted('team.analytics', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  delete from public.analytics_reads x where x.id = p_id returning * into a;
  if a.id is null then return jsonb_build_object('error', 'not-found'); end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, m.email), 'team.changed', 'Analytics',
          'Analysis version ' || a.version || ' deleted · ' || a.period);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.announcement_delete(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  a public.announcements;
begin
  if me.id is null or not public.ops_granted('team.announce', 'manage') then return jsonb_build_object('error', 'denied'); end if;
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

create or replace function public.campaign_file_delete(p_file uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me   public.team_members;
  d    public.campaign_deliverables%rowtype;
  o    public.campaign_options%rowtype;
  c    public.campaigns%rowtype;
  cr   text;
begin
  if not public.ops_granted('campaigns.files_delete', 'manage') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into d from public.campaign_deliverables where id = p_file for update;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.hidden_at is null then return jsonb_build_object('error', 'not-hidden'); end if;
  select * into o from public.campaign_options where id = d.option_id;
  select * into c from public.campaigns where id = o.campaign_id;
  if not public.client_scope_ok('campaign', c.id, 'manage') then
    return jsonb_build_object('error', 'client-scope');
  end if;
  select cx.name into cr from public.creators cx where cx.id = o.creator_id;
  delete from public.campaign_deliverables where id = d.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'campaign.file_deleted', c.title,
          coalesce(cr, 'Creator') || ' · ' || coalesce(d.name, 'file'));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.department_delete(p_key text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me public.team_members; v_old public.departments; v_n int;
begin
  if not public.ops_granted('team.settings', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  select * into v_old from public.departments d where d.key = p_key for update;
  if v_old.key is null then return jsonb_build_object('error', 'not-found'); end if;
  select count(*)::int into v_n from public.team_members t where t.department = p_key;
  if v_n > 0 or exists (select 1 from public.perf_people p where p.department = p_key)
     or exists (select 1 from public.perf_dept_scores s where s.department = p_key) then
    return jsonb_build_object('error', 'in-use', 'members', v_n);
  end if;
  delete from public.departments d where d.key = p_key;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_me.name, 'admin'), 'team.changed', 'Departments', 'Removed: ' || v_old.name);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.industry_delete(p_name text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_n int;
begin
  if not public.ops_granted('team.settings', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  perform pg_advisory_xact_lock(hashtextextended('industries', 0));
  if not exists (select 1 from public.industries i where i.name = p_name) then return jsonb_build_object('error', 'not-found'); end if;
  -- Other stays, the website's last choice (2026-11-04, review 6).
  if p_name = 'Other' then return jsonb_build_object('error', 'fixed'); end if;
  select count(*)::int into v_n from public.clients c where c.industry = p_name;
  if v_n > 0 then return jsonb_build_object('error', 'in-use', 'clients', v_n); end if;
  delete from public.industries i where i.name = p_name;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Industries', 'Deleted: ' || p_name);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.public_holiday_delete(p_day date)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_me public.team_members;
  v_old public.public_holidays;
begin
  if not public.ops_granted('team.settings', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  select * into v_old from public.public_holidays h where h.day = p_day;
  if v_old.day is null then return jsonb_build_object('error', 'not-found'); end if;
  delete from public.public_holidays h where h.day = p_day;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_me.name, 'admin'), 'team.changed', 'Public holidays',
    'Removed: ' || public.register_day(v_old.day) || ' · ' || v_old.name);
  return jsonb_build_object('ok', true, 'day', p_day, 'name', v_old.name);
end $$;

create or replace function public.tax_codes_delete(p_codes text[])
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members := public.ops_me();
  v_codes text[];
  v_used text[];
  v_gone text[];
begin
  if v_me.id is null or not public.ops_granted('team.settings', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select array_agg(distinct btrim(c)) into v_codes from unnest(coalesce(p_codes, '{}')) c where btrim(coalesce(c, '')) <> '';
  if v_codes is null or array_length(v_codes, 1) > 100 then return jsonb_build_object('error', 'bad-row'); end if;
  perform 1 from public.tax_codes t where t.code = any(v_codes) for update;
  select array_agg(t.code order by t.code) into v_used
    from public.tax_codes t where t.code = any(v_codes) and public.tax_code_uses(t.code) > 0;
  if v_used is not null then return jsonb_build_object('error', 'in-use', 'codes', to_jsonb(v_used)); end if;
  with d as (delete from public.tax_codes t where t.code = any(v_codes) returning t.code)
  select array_agg(d.code order by d.code) into v_gone from d;
  if v_gone is not null then
    insert into public.activity_log (actor, action, subject, detail)
    values (v_me.name, 'team.changed', 'Tax codes',
            array_length(v_gone, 1) || ' deleted: ' || array_to_string(v_gone, ', '));
  end if;
  return public.tax_codes_list() || jsonb_build_object('deleted', coalesce(array_length(v_gone, 1), 0));
end $$;

create or replace function public.doc_type_delete(p_id text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_t public.doc_types%rowtype;
  v_docs integer;
begin
  if not public.ops_granted('register.types', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_t from public.doc_types d where d.id = p_id for update;
  if v_t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  /* The types the portal itself reads by name stay: the quotation's cover
     letter, the supplier's letter and its Service Agreement. */
  if v_t.id in ('quote_cover', 'supplier_letter', 'supplier_sca') then return jsonb_build_object('error', 'built-in'); end if;
  select count(*) into v_docs from public.documents x where x.type_id = p_id;
  if v_docs > 0 then return jsonb_build_object('error', 'in-use', 'documents', v_docs); end if;
  delete from public.doc_types d where d.id = p_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(me.name, lower(auth.jwt() ->> 'email')), 'team.changed', 'Document types', v_t.name || ' · Deleted');
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.handbook_delete(p_id uuid, p_title text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  d public.handbook_docs;
  v_paths jsonb;
begin
  if not public.ops_granted('team.handbook', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into d from public.handbook_docs h where h.id = p_id;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if lower(btrim(coalesce(p_title, ''))) <> lower(btrim(d.title)) then
    return jsonb_build_object('error', 'mismatch');
  end if;
  select coalesce(jsonb_agg(v.file_path order by v.version_no), '[]'::jsonb) into v_paths
    from public.handbook_versions v where v.doc_id = p_id;
  delete from public.handbook_docs h where h.id = p_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'handbook.deleted', d.title,
          jsonb_array_length(v_paths) || case when jsonb_array_length(v_paths) = 1 then ' version' else ' versions' end);
  return jsonb_build_object('ok', true, 'paths', v_paths);
end $$;

create or replace function public.hiring_delete(p_id uuid, p_name text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  c public.hiring_candidates;
begin
  if me.id is null or not public.ops_granted('team.hiring', 'manage') then return jsonb_build_object('error', 'denied'); end if;
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

create or replace function public.hiring_scorecard_delete(p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); s public.hiring_scorecards;
begin
  if me.id is null or not public.ops_granted('team.hiring', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into s from public.hiring_scorecards where id = p_id for update;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if s.standard then return jsonb_build_object('error', 'standard'); end if;
  delete from public.hiring_scorecards where id = s.id;
  insert into public.activity_log (actor, action, subject, detail) values (me.email, 'team.changed', 'Interview scorecards', s.position || ' deleted');
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.ops_template_delete(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  m public.team_members := public.ops_me();
  t public.ops_task_templates;
  v_tasks integer; v_rules integer;
begin
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_granted('ops.workflows', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.ops_task_templates x where x.id = p_id for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select count(*) into v_tasks from public.ops_tasks x where x.template_id = p_id;
  select count(*) into v_rules from public.ops_recurring_rules x where x.template_id = p_id;
  if v_tasks + v_rules > 0 then
    return jsonb_build_object('error', 'in-use', 'tasks', v_tasks, 'rules', v_rules);
  end if;
  delete from public.ops_task_templates x where x.id = p_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (m.name, 'team.changed', 'Task templates', t.name || ' · Deleted');
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.team_notice_delete(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v public.team_notices;
  n int;
begin
  if me.id is null or not public.ops_granted('team.notice', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into v from public.team_notices tn where tn.id = p_id for update;
  if v.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v.withdrawn_at is null then return jsonb_build_object('error', 'live'); end if;
  delete from public.ops_notifications o where o.notice_id = v.id;
  get diagnostics n = row_count;
  delete from public.team_notices tn where tn.id = v.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Notices', 'Deleted: ' || v.title);
  return jsonb_build_object('ok', true, 'copies', n);
end $$;

revoke all on function public.analytics_read_delete(uuid) from public, anon;
grant execute on function public.analytics_read_delete(uuid) to authenticated;
revoke all on function public.announcement_delete(uuid) from public, anon;
grant execute on function public.announcement_delete(uuid) to authenticated;
revoke all on function public.campaign_file_delete(uuid) from public, anon;
grant execute on function public.campaign_file_delete(uuid) to authenticated;
revoke all on function public.department_delete(text) from public, anon;
grant execute on function public.department_delete(text) to authenticated;
revoke all on function public.industry_delete(text) from public, anon;
grant execute on function public.industry_delete(text) to authenticated;
revoke all on function public.public_holiday_delete(date) from public, anon;
grant execute on function public.public_holiday_delete(date) to authenticated;
revoke all on function public.tax_codes_delete(text[]) from public, anon;
grant execute on function public.tax_codes_delete(text[]) to authenticated;
revoke all on function public.doc_type_delete(text) from public, anon;
grant execute on function public.doc_type_delete(text) to authenticated;
revoke all on function public.handbook_delete(uuid, text) from public, anon;
grant execute on function public.handbook_delete(uuid, text) to authenticated;
revoke all on function public.hiring_delete(uuid, text) from public, anon;
grant execute on function public.hiring_delete(uuid, text) to authenticated;
revoke all on function public.hiring_scorecard_delete(uuid) from public, anon;
grant execute on function public.hiring_scorecard_delete(uuid) to authenticated;
revoke all on function public.ops_template_delete(uuid) from public, anon;
grant execute on function public.ops_template_delete(uuid) to authenticated;
revoke all on function public.team_notice_delete(uuid) from public, anon;
grant execute on function public.team_notice_delete(uuid) to authenticated;

insert into public.delete_kinds (kind, section, id_arg, word, label_table, label_key, label_col) values
  ('rpc:analytics_read_delete',   'team.analytics',         'p_id',   'AI analysis',         'analytics_reads',    'id',   'period'),
  ('rpc:announcement_delete',     'team.announce',          'p_id',   'Announcement',        'announcements',      'id',   'body_en'),
  ('rpc:campaign_file_delete',    'campaigns.files_delete', 'p_file', 'Approved file',       null,                 null,   null),
  ('rpc:department_delete',       'team.settings',          'p_key',  'Department',          'departments',        'key',  'name'),
  ('rpc:industry_delete',         'team.settings',          'p_name', 'Industry',            'industries',         'name', 'name'),
  ('rpc:public_holiday_delete',   'team.settings',          'p_day',  'Public holiday',      'public_holidays',    'day',  'name'),
  ('rpc:tax_codes_delete',        'team.settings',          'p_codes','Tax code',            null,                 null,   null),
  ('rpc:doc_type_delete',         'register.types',         'p_id',   'Document type',       'doc_types',          'id',   'name'),
  ('rpc:handbook_delete',         'team.handbook',          'p_id',   'Handbook file',       'handbook_docs',      'id',   'title'),
  ('rpc:hiring_delete',           'team.hiring',            'p_id',   'Candidate',           'hiring_candidates',  'id',   'name'),
  ('rpc:hiring_scorecard_delete', 'team.hiring',            'p_id',   'Interview scorecard', 'hiring_scorecards',  'id',   'position'),
  ('rpc:ops_template_delete',     'ops.workflows',          'p_id',   'Task template',       'ops_task_templates', 'id',   'name'),
  ('rpc:team_notice_delete',      'team.notice',            'p_id',   'Notice',              'team_notices',       'id',   'title')
on conflict (kind) do update set section = excluded.section, id_arg = excluded.id_arg, word = excluded.word,
  label_table = excluded.label_table, label_key = excluded.label_key, label_col = excluded.label_col;

create or replace function public.delete_request_file(p_kind text, p_args jsonb, p_reason text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me       public.team_members := public.ops_me();
  k        public.delete_kinds;
  v_rec    text;
  v_label  text;
  v_client uuid;
  v_why    text := btrim(regexp_replace(coalesce(p_reason, ''), '\s+', ' ', 'g'));
  v_id     uuid;
  v_ids    uuid[];
  v_n      integer;
  v_seen   integer;
  v_names  text;
  v_cls    uuid[];
  v_codes  text[];
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into k from public.delete_kinds x where x.kind = p_kind;
  if k.kind is null then return jsonb_build_object('error', 'bad-kind'); end if;
  /* A granted part (an admin tool) never takes its section's level: it is
     asked as its delete asks it (DELETES AT FULL CONTROL, 2026-11-27). */
  if exists (select 1 from public.access_keys a where a.key = k.section and a.tier = 'granted') then
    if not public.ops_granted(k.section, 'work') then return jsonb_build_object('error', 'denied'); end if;
    if public.ops_granted(k.section, 'manage') then return jsonb_build_object('error', 'may-delete'); end if;
  else
    if not public.allowed(k.section, 'work') then return jsonb_build_object('error', 'denied'); end if;
    if public.allowed(k.section, 'manage') then return jsonb_build_object('error', 'may-delete'); end if;
  end if;
  if p_args is null or jsonb_typeof(p_args) <> 'object' or length(p_args::text) > 4000 then
    return jsonb_build_object('error', 'bad-request');
  end if;
  if length(v_why) < 3 or length(v_why) > 500 then return jsonb_build_object('error', 'bad-reason'); end if;
  if jsonb_typeof(p_args -> k.id_arg) = 'array' then
    v_rec := null;
    v_n := jsonb_array_length(p_args -> k.id_arg);
    if v_n not between 1 and 200 then return jsonb_build_object('error', 'bad-request'); end if;
    if k.kind = 'rpc:tax_codes_delete' then
      /* Tax codes, deleted several at once: every one held and named. */
      select array_agg(distinct btrim(e) order by btrim(e)) into v_codes
        from jsonb_array_elements_text(p_args -> k.id_arg) e where btrim(coalesce(e, '')) <> '';
      if v_codes is null or array_length(v_codes, 1) > 100 then return jsonb_build_object('error', 'bad-request'); end if;
      select count(*) into v_seen from public.tax_codes t where t.code = any(v_codes);
      if v_seen <> array_length(v_codes, 1) then return jsonb_build_object('error', 'not-found'); end if;
      v_label := v_seen::text || ' ' || lower(k.word) || case when v_seen = 1 then '' else 's' end || ' · ' || array_to_string(v_codes[1:3], ', ')
        || case when v_seen > 3 then ' and ' || (v_seen - 3)::text || ' more' else '' end;
    else
    /* A list (several tasks): every one held, each in the requester's
       sight, their names kept for the admin's question. */
    if k.kind <> 'rpc:ops_delete_tasks' then return jsonb_build_object('error', 'bad-request'); end if;
    begin
      select array_agg(distinct e::uuid) into v_ids from jsonb_array_elements_text(p_args -> k.id_arg) e;
    exception when invalid_text_representation then return jsonb_build_object('error', 'bad-request');
    end;
    select count(*), string_agg(t.title, ', ' order by t.title) filter (where t.rn <= 3),
           array_agg(distinct t.client_id) filter (where t.client_id is not null)
      into v_seen, v_names, v_cls
      from (select x.id, x.title, x.client_id, row_number() over (order by x.title) as rn
              from public.ops_tasks x where x.id = any(v_ids) and public.ops_may_see_task(x.id)
               and (x.client_id is null or public.client_seen(x.client_id, 'view'))) t;
    if v_seen <> coalesce(array_length(v_ids, 1), 0) then return jsonb_build_object('error', 'not-found'); end if;
    v_label := v_seen::text || ' ' || lower(k.word) || ' · ' || coalesce(v_names, '')
      || case when v_seen > 3 then ' and ' || (v_seen - 3)::text || ' more' else '' end;
    if coalesce(array_length(v_cls, 1), 0) = 1 then v_client := v_cls[1]; end if;
    end if;
  else
    v_rec := nullif(btrim(coalesce(p_args ->> k.id_arg, '')), '');
    if v_rec is null or length(v_rec) > 100 then return jsonb_build_object('error', 'bad-request'); end if;
    if k.label_table is not null then
      execute format('select %I::text from public.%I where %I::text = $1', k.label_col, k.label_table, k.label_key)
        into v_label using v_rec;
      if not found then return jsonb_build_object('error', 'not-found'); end if;
      begin
        execute format('select client_id from public.%I where %I::text = $1', k.label_table, k.label_key)
          into v_client using v_rec;
      exception when undefined_column then v_client := null;
      end;
      if k.label_table = 'clients' then v_client := v_rec::uuid; end if;
      /* A supplier's client is the one it is linked to, not its owner. */
      if k.label_table = 'suppliers' then v_client := null; end if;
    elsif k.kind = 'rpc:sm_report_version_delete' then
      /* A report's version: its report's title and number. */
      select coalesce(nullif(btrim(r.title), ''), 'Report') || ' · version ' || v.version_no, r.client_id
        into v_label, v_client
        from public.sm_report_versions v join public.sm_reports r on r.id = v.report_id
       where v.id::text = v_rec;
      if not found then return jsonb_build_object('error', 'not-found'); end if;
    elsif k.kind = 'rpc:campaign_file_delete' then
      /* An approved file: its creator and its name, its campaign's client. */
      select coalesce(c.name, 'Creator') || ' · ' || coalesce(nullif(btrim(d.name), ''), 'File'), g.client_id
        into v_label, v_client
        from public.campaign_deliverables d
        join public.campaign_options o on o.id = d.option_id
        join public.campaigns g on g.id = o.campaign_id
        left join public.creators c on c.id = o.creator_id
       where d.id::text = v_rec;
      if not found then return jsonb_build_object('error', 'not-found'); end if;
    elsif k.kind = 'table:campaign_options' then
      /* A booking: its creator and campaign. */
      select coalesce(c.name, 'Creator') || ' · ' || coalesce(nullif(btrim(g.title), ''), 'Campaign'), g.client_id
        into v_label, v_client
        from public.campaign_options o
        join public.campaigns g on g.id = o.campaign_id
        left join public.creators c on c.id = o.creator_id
       where o.id::text = v_rec;
      if not found then return jsonb_build_object('error', 'not-found'); end if;
    else
      return jsonb_build_object('error', 'bad-kind');
    end if;
    if v_client is not null and not public.client_seen(v_client, 'view') then
      return jsonb_build_object('error', 'not-found');
    end if;
    v_label := coalesce(nullif(btrim(coalesce(v_label, '')), ''), k.word);
  end if;
  perform pg_advisory_xact_lock(hashtextextended('delete-request:' || me.id::text, 0));
  if (select count(*) from public.delete_requests x where x.requested_by = me.id
        and x.created_at > now() - interval '24 hours') >= 30 then
    return jsonb_build_object('error', 'too-many');
  end if;
  if v_rec is not null and exists (select 1 from public.delete_requests x
       where x.kind = k.kind and x.record = v_rec and x.state in ('open', 'approving')) then
    return jsonb_build_object('error', 'already');
  end if;
  insert into public.delete_requests (kind, args, record, label, client_id, reason, requested_by)
  values (k.kind, p_args, v_rec, left(v_label, 200), v_client, v_why, me.id)
  returning id into v_id;
  insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
  select m.id, 'delete.request', 'Delete requested · ' || k.word || ' · ' || left(v_label, 120),
         me.name || ' · ' || v_why,
         v_client, 'delreq:' || v_id || ':' || m.id
    from public.team_members m
   where m.active and (m.is_admin or m.role = 'admin') and m.id <> me.id
  on conflict (dedupe_key) do nothing;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Delete requests', 'Requested: ' || k.word || ' · ' || left(v_label, 120) || ' · ' || v_why);
  return jsonb_build_object('ok', true, 'id', v_id, 'label', v_label, 'word', k.word);
end $$;
revoke all on function public.delete_request_file(text, jsonb, text) from public, anon;
grant execute on function public.delete_request_file(text, jsonb, text) to authenticated;

-- END OF DELETES AT FULL CONTROL ---------------------------------------------

select public.functions_tidy();
