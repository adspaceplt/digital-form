-- ===========================================================================
-- ADMIN PARTS — every act an admin alone could take is a granted part: an
-- admin holds it, any other group only once it is set in its Team panel.
-- 2026-10-07. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the
-- two. Runs after WHITE LABEL BRAND LOGO.
--
-- WHAT CHANGED (the user, 2026-10-07: "keep to auto admin only but then
-- allow changes to add permissions for other user groups too. make it
-- controllable")
--   Each check below asked `allowed('admin')` (or `perf_is_admin()`, an
--   admin alone); each now asks `ops_granted(key, 'work')`, which answers
--   true for an admin and for a group whose access holds the key at Work.
--   No group is given any of them here.
--     ops.numbering      ops_next_task_no, ops_set_next_task_no
--     ops.override       ops_owner_may_move (move a task one does not own),
--                        ops_request_due_change (move a final date directly)
--     team.perfadmin     perf_is_admin(): revenue and profit, Performance
--                        settings, a month's record removed
--     team.settings      app_settings_set (Follow-up limits, Tax and terms,
--                        Due dates); app_settings_read's `admin` answers it
--     team.upgrade       maintenance_set
--     team.handbook      handbook_save, handbook_add_version,
--                        handbook_archive, handbook_delete, and the bucket's
--                        add and remove policies
--     team.invite        the invite-member edge function (asked there)
--     reports.transfer   sm_report_move
--     reports.ai         ai_draft_usage, ai_draft_set_limit
--   The AI limits an admin is given (`admin`, `report_admin`, `check_admin`)
--   stay an admin's: they are a role's allowance, not a permission.
--
-- ROLLBACK
--   Run each function's previous section again (MAINTENANCE MODE, APP
--   SETTINGS, HANDBOOK, …); the parts then grant nothing beyond an admin.
-- ===========================================================================

create or replace function public.perf_is_admin()
returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return public.ops_granted('team.perfadmin', 'work');
end $$;
revoke all on function public.perf_is_admin() from public, anon, authenticated;

create or replace function public.ops_next_task_no()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  lv   bigint;
  ic   boolean;
  nxt  bigint;
  top  bigint;
begin
  if not public.ops_granted('ops.numbering', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select last_value, is_called into lv, ic from public.ops_task_no_seq;
  nxt := case when ic then lv + 1 else lv end;
  select max(task_no) into top from public.ops_tasks;
  return jsonb_build_object('next', nxt, 'serial', public.ops_serial(nxt),
    'highest', top, 'highest_serial', case when top is null then null else public.ops_serial(top) end);
end $$;
grant execute on function public.ops_next_task_no() to authenticated;

create or replace function public.ops_set_next_task_no(p_next bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m    public.team_members;
  top  bigint;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_granted('ops.numbering', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_next is null or p_next < 1 or p_next > 9999999 then
    return jsonb_build_object('error', 'bad-number');
  end if;
  select max(task_no) into top from public.ops_tasks;
  if top is not null and p_next <= top then
    return jsonb_build_object('error', 'number-taken', 'highest', public.ops_serial(top));
  end if;
  perform setval('public.ops_task_no_seq', p_next, false);
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, m.email), 'ops.numbering', 'My Work',
          'Next task number set to ' || public.ops_serial(p_next));
  return public.ops_next_task_no();
end $$;
grant execute on function public.ops_set_next_task_no(bigint) to authenticated;

create or replace function public.ops_owner_may_move(p_task uuid)
returns boolean
language sql security definer stable set search_path = public as $$
  select public.ops_granted('ops.override', 'work')
      or not exists (select 1 from public.ops_task_assignees a
                      where a.task_id = p_task and a.responsibility = 'owner' and a.ended_at is null)
      or exists (select 1 from public.ops_task_assignees a
                  where a.task_id = p_task and a.responsibility = 'owner' and a.ended_at is null
                    and a.team_member_id = (public.ops_me()).id)
$$;
grant execute on function public.ops_owner_may_move(uuid) to authenticated;

create or replace function public.ops_request_due_change(
  p_task uuid, p_kind text, p_value timestamptz, p_reason text,
  p_note text default null, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m     public.team_members;
  t     public.ops_tasks;
  who   uuid;
  was   timestamptz;
  v_id  uuid;
  nm    text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_reason, '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  if p_kind not in ('first_draft', 'final') then return jsonb_build_object('error', 'bad-kind'); end if;
  if p_value is null then return jsonb_build_object('error', 'no-date'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;

  /* Refused before an ask is raised as well as before a move is made: an ask
     nobody could approve without breaking the plan is one to turn away at the
     door, with the word the move itself would have used. */
  if not public.ops_due_order_ok(
       case when p_kind = 'first_draft' then p_value else t.current_first_draft_due_at end,
       case when p_kind = 'final'       then p_value else t.current_final_due_at end) then
    return jsonb_build_object('error', 'draft-not-before-final');
  end if;

  who := public.ops_due_decider(p_task, p_kind);
  /* Nobody to ask — the team's own first draft milestone, or a task whose
     creator is the person asking — so the move is theirs to make and the
     round would be a form with one name on both ends. */
  /* An admin moves any date directly: the round protects the person who set
     the date from somebody else, and an admin is the one who may overwrite
     anybody's. The move still files its event and keeps the original. */
  if who is null or who = m.id or public.ops_granted('ops.override', 'work') then
    return public.ops_change_due_date(p_task, p_kind, p_value, p_reason, p_note, p_version);
  end if;

  was := case when p_kind = 'final' then t.current_final_due_at
              else t.current_first_draft_due_at end;

  insert into public.ops_due_requests
    (task_id, kind, was_at, wants_at, reason, note, asked_by, decider_id)
  values (p_task, p_kind, was, p_value, p_reason, nullif(btrim(p_note), ''), m.id, who)
  on conflict (task_id, kind) where state = 'asked' do nothing
  returning id into v_id;

  /* The same press twice is the same ask. The open one is handed back so the
     page can say it is already with somebody. */
  if v_id is null then
    select id into v_id from public.ops_due_requests
      where task_id = p_task and kind = p_kind and state = 'asked';
    return jsonb_build_object('ok', true, 'repeat', true, 'request', v_id,
                              'task', public.ops_task_json(p_task));
  end if;

  select name into nm from public.team_members where id = m.id;
  perform public.ops_notify(who, p_task, 'due_requested',
    'Extension requested',
    coalesce(nm, 'Somebody') || ' asked to move ' ||
      case when p_kind = 'final' then 'the due date' else 'the first draft date' end ||
      ' to ' || to_char(timezone('Asia/Kuala_Lumpur', p_value), 'DD Mon YYYY'),
    'due_req:' || v_id::text);

  perform public.ops_log(p_task, 'due_requested',
    jsonb_build_object('kind', p_kind, 'value', was),
    jsonb_build_object('kind', p_kind, 'value', p_value),
    jsonb_build_object('reason', p_reason, 'note', p_note, 'request', v_id));

  return jsonb_build_object('ok', true, 'request', v_id, 'asked', true,
                            'task', public.ops_task_json(p_task));
end $$;
grant execute on function public.ops_request_due_change(uuid, text, timestamptz, text, text, integer) to authenticated;

create or replace function public.app_settings_set(p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members; v_k text; v_v numeric; v_was numeric; v_name text; v_unit text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_keys constant text[] := array['lead_followup_hours', 'proposal_followup_days', 'sst_pct',
    'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_24', 'report_due_days', 'revision_due_days'];
  v_moved text[] := '{}';
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  if p_from is null or p_from < v_today then return jsonb_build_object('error', 'past', 'today', v_today); end if;
  if jsonb_typeof(p_values) is distinct from 'object' then return jsonb_build_object('error', 'bad-value'); end if;
  for v_k in select jsonb_object_keys(p_values) loop
    if not (v_k = any(v_keys)) or jsonb_typeof(p_values -> v_k) <> 'number' then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
    v_v := (p_values ->> v_k)::numeric;
    if round(v_v, 2) <> v_v
       or (v_k = 'lead_followup_hours' and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k = 'proposal_followup_days' and (v_v < 1 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'report_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'revision_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'sst_pct' and (v_v < 0 or v_v > 100))
       or (v_k like 'term_%' and (v_v < -100 or v_v > 100)) then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
  end loop;
  for v_k in select jsonb_object_keys(p_values) loop
    v_v := (p_values ->> v_k)::numeric;
    v_was := public.app_setting(v_k, p_from);
    if v_was is distinct from v_v then
      insert into public.app_settings (key, from_date, value, set_by, set_at)
      values (v_k, p_from, v_v, v_me.id, now())
      on conflict (key, from_date) do update set value = excluded.value, set_by = excluded.set_by, set_at = now();
      v_name := case v_k when 'lead_followup_hours' then 'A lead waits' when 'proposal_followup_days' then 'A proposal waits'
        when 'sst_pct' then 'SST' when 'term_1_3' then '1 to 3 months' when 'term_4_5' then '4 and 5 months'
        when 'term_6_11' then '6 to 11 months' when 'term_12_23' then '12 to 23 months' when 'term_24' then '24 months and more'
        when 'revision_due_days' then 'Revision due' else 'Report due' end;
      v_unit := case when v_k = 'lead_followup_hours' then ' hours' when v_k in ('proposal_followup_days', 'report_due_days', 'revision_due_days') then ' days'
        else '%' end;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(v_me.name, 'admin'), 'team.changed', 'Settings',
              v_name || ': ' || trim(to_char(v_was, 'FM999999990.99'), '.') || v_unit || ' → ' ||
              trim(to_char(v_v, 'FM999999990.99'), '.') || v_unit || ' · from ' || public.register_day(p_from));
      v_moved := v_moved || v_k;
    end if;
  end loop;
  return public.app_settings_read() || jsonb_build_object('changed', to_jsonb(v_moved));
end $$;
revoke all on function public.app_settings_set(date, jsonb) from public, anon;

create or replace function public.app_settings_read()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_team boolean := public.is_team();
begin
  return jsonb_build_object(
    'today', (now() at time zone 'Asia/Kuala_Lumpur')::date,
    'admin', v_team and public.ops_granted('team.settings', 'work'),
    'settings', coalesce((select jsonb_agg(jsonb_build_object('key', s.key, 'from', s.from_date, 'value', s.value,
                   'by', case when v_team then (select t.name from public.team_members t where t.id = s.set_by) end,
                   'at', case when v_team then s.set_at end)
                 order by s.key, s.from_date) from public.app_settings s), '[]'::jsonb));
end $$;

create or replace function public.maintenance_set(p_on boolean, p_note text default null,
                                                  p_starts timestamptz default null,
                                                  p_ends timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_was boolean;
  v_who text;
  v_on boolean := coalesce(p_on, false);
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_when text := '';
begin
  if not public.ops_granted('team.upgrade', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  if v_on and p_ends is not null and p_ends <= greatest(coalesce(p_starts, now()), now()) then
    return jsonb_build_object('error', 'bad-window');
  end if;
  select coalesce(t.name, t.email) into v_who from public.team_members t
   where lower(t.email) = lower(auth.jwt() ->> 'email') and t.active limit 1;
  select f.on_now and (f.ends_at is null or f.ends_at > now()) into v_was
    from public.app_flags f where f.key = 'maintenance';
  insert into public.app_flags (key, on_now, note, starts_at, ends_at, set_by, set_at)
  values ('maintenance', v_on, case when v_on then left(v_note, 300) end,
          case when v_on and p_starts > now() then p_starts end,
          case when v_on then p_ends end, v_who, now())
  on conflict (key) do update
    set on_now = excluded.on_now, note = excluded.note, starts_at = excluded.starts_at,
        ends_at = excluded.ends_at, set_by = excluded.set_by, set_at = excluded.set_at;
  if v_on and p_starts > now() then
    v_when := ' · from ' || regexp_replace(to_char(p_starts at time zone 'Asia/Kuala_Lumpur', 'FMDD Mon YYYY HH24:MI'), '\mSep\M', 'Sept');
  end if;
  if v_on and p_ends is not null then
    v_when := v_when || ' · until ' || regexp_replace(to_char(p_ends at time zone 'Asia/Kuala_Lumpur', 'FMDD Mon YYYY HH24:MI'), '\mSep\M', 'Sept');
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_who, 'admin'), 'team.changed', 'Portal',
          'Upgrade mode: ' || case when coalesce(v_was, false) then 'on' else 'off' end || ' → ' ||
          case when v_on then 'on' else 'off' end || v_when ||
          case when v_on then coalesce(' · ' || left(v_note, 300), '') else '' end);
  return public.maintenance_state();
end $$;
revoke all on function public.maintenance_set(boolean, text, timestamptz, timestamptz) from public, anon;
grant execute on function public.maintenance_set(boolean, text, timestamptz, timestamptz) to authenticated;

create or replace function public.handbook_save(p_id uuid, p_title text, p_category text, p_summary text, p_link text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_title text := btrim(coalesce(p_title, ''));
  v_link text := nullif(btrim(coalesce(p_link, '')), '');
  v_changed text;
  d public.handbook_docs;
begin
  if not public.ops_granted('team.handbook', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if v_title = '' then return jsonb_build_object('error', 'no-title'); end if;
  if coalesce(p_category, '') not in ('handbook', 'sop', 'policy', 'template', 'other') then
    return jsonb_build_object('error', 'bad-category');
  end if;
  if v_link is not null and v_link !~ '^https://' then return jsonb_build_object('error', 'bad-link'); end if;
  select * into d from public.handbook_docs h where h.id = p_id;
  if d.id is null then
    insert into public.handbook_docs (id, title, category, summary, link_url, created_by)
    values (coalesce(p_id, gen_random_uuid()), v_title, p_category, nullif(btrim(coalesce(p_summary, '')), ''), v_link, who)
    returning * into d;
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'handbook.added', d.title, case d.category when 'handbook' then 'Employee Handbook'
      when 'sop' then 'SOPs' when 'policy' then 'Policies' when 'template' then 'Templates and forms' else 'Other' end);
  else
    v_changed := concat_ws(', ',
      case when d.title is distinct from v_title then 'title' end,
      case when d.category is distinct from p_category then 'category' end,
      case when d.summary is distinct from nullif(btrim(coalesce(p_summary, '')), '') then 'summary' end,
      case when d.link_url is distinct from v_link then 'link' end);
    if v_changed = '' then return jsonb_build_object('ok', true, 'id', d.id, 'changed', false); end if;
    update public.handbook_docs h
       set title = v_title, category = p_category,
           summary = nullif(btrim(coalesce(p_summary, '')), ''), link_url = v_link, updated_at = now()
     where h.id = p_id returning * into d;
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'handbook.edited', d.title, upper(left(v_changed, 1)) || substr(v_changed, 2));
  end if;
  return jsonb_build_object('ok', true, 'id', d.id);
end $$;


create or replace function public.handbook_add_version(p_doc uuid, p_path text, p_name text, p_size bigint, p_mime text, p_note text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  d public.handbook_docs;
  n integer;
begin
  if not public.ops_granted('team.handbook', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into d from public.handbook_docs h where h.id = p_doc for update;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if coalesce(p_path, '') = '' or position(p_doc::text || '/' in p_path) <> 1 then
    return jsonb_build_object('error', 'bad-path');
  end if;
  if btrim(coalesce(p_name, '')) = '' then return jsonb_build_object('error', 'no-file'); end if;
  select coalesce(max(v.version_no), 0) + 1 into n from public.handbook_versions v where v.doc_id = p_doc;
  insert into public.handbook_versions (doc_id, version_no, file_path, file_name, file_size, mime, note, created_by)
  values (p_doc, n, p_path, btrim(p_name), p_size, p_mime, nullif(btrim(coalesce(p_note, '')), ''), who);
  update public.handbook_docs h set current_version = n, updated_at = now() where h.id = p_doc;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'handbook.version', d.title,
          concat_ws(' · ', 'Version ' || n, btrim(p_name), nullif(btrim(coalesce(p_note, '')), '')));
  return jsonb_build_object('ok', true, 'version', n);
end $$;


create or replace function public.handbook_archive(p_id uuid, p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  d public.handbook_docs;
begin
  if not public.ops_granted('team.handbook', 'work') then return jsonb_build_object('error', 'denied'); end if;
  update public.handbook_docs h
     set archived_at = case when p_on then coalesce(h.archived_at, now()) end
   where h.id = p_id returning * into d;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, case when p_on then 'handbook.archived' else 'handbook.restored' end, d.title, null);
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
  if not public.ops_granted('team.handbook', 'work') then return jsonb_build_object('error', 'denied'); end if;
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


create or replace function public.sm_report_move(p_id uuid, p_client uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  c public.clients;
  was text;
begin
  if me.id is null or not public.ops_granted('reports.transfer', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'draft' then return jsonb_build_object('error', 'not-draft', 'status', r.status); end if;
  if r.brand_id is not null then return jsonb_build_object('error', 'white-label'); end if;
  select * into c from public.clients where id = p_client;
  if c.id is null or c.stage <> 'active' then return jsonb_build_object('error', 'not-active'); end if;
  if c.id = r.client_id then return jsonb_build_object('ok', true, 'client_id', c.id); end if;
  if exists (select 1 from public.sm_reports x
              where x.client_id = c.id and x.kind = r.kind and x.id <> r.id and x.brand_id is null
                and x.period_start <= r.period_end and x.period_end >= r.period_start) then
    return jsonb_build_object('error', 'exists');
  end if;
  select k.name into was from public.clients k where k.id = r.client_id;
  perform public.sm_report_log(p_id, 'report.saved', 'Client: ' || coalesce(was, 'not set') || ' → ' || c.name);
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set client_id = c.id where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  update public.ai_drafts set client_id = c.id where report_id = p_id;
  perform public.sm_report_log(p_id, 'report.saved', 'Client: ' || coalesce(was, 'not set') || ' → ' || c.name);
  return jsonb_build_object('ok', true, 'client_id', c.id);
end $$;
revoke all on function public.sm_report_move(uuid, uuid) from public, anon, authenticated;
grant execute on function public.sm_report_move(uuid, uuid) to authenticated;

create or replace function public.ai_draft_usage()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_day timestamptz := public.ai_draft_day();
  v_month timestamptz := now() - interval '30 days';
begin
  if not public.ops_granted('reports.ai', 'work') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object(
    'person', public.ai_draft_limit('person', 10),
    'admin', public.ai_draft_limit('admin', 20),
    'report', public.ai_draft_limit('report', 1),
    'report_admin', public.ai_draft_limit('report_admin', 5),
    'check', public.ai_draft_limit('check', 1),
    'check_admin', public.ai_draft_limit('check_admin', 5),
    'resets_at', v_day + interval '1 day',
    'people', coalesce((select jsonb_agg(s.x order by s.x ->> 'name') from (
      select jsonb_build_object(
        'id', t.id, 'name', t.name, 'code', t.staff_code, 'group', g.name, 'group_slug', t.role,
        'admin', coalesce(t.is_admin, false) or t.role = 'admin',
        'day', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed'),
        'month', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_month and d.outcome <> 'failed'),
        'limit', (select l.daily from public.ai_draft_limits l where l.scope = t.id::text),
        'cap', public.ai_day_cap(t)) as x
        from public.team_members t
        left join public.team_roles g on g.slug = t.role
       where t.active
         and (coalesce(t.is_admin, false) or t.role = 'admin'
              or public.level_rank(coalesce(t.access ->> 'reports', 'none')) >= public.level_rank('work')
              or exists (select 1 from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_month))
    ) s), '[]'::jsonb));
end $$;
revoke all on function public.ai_draft_usage() from public, anon, authenticated;
grant execute on function public.ai_draft_usage() to authenticated;

create or replace function public.ai_draft_set_limit(p_scope text, p_daily integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_who text;
  v_name text;
  v_was integer;
  v_def integer;
  v_unit text := ' a day';
  v_scope text := btrim(coalesce(p_scope, ''));
  t public.team_members;
begin
  if not public.ops_granted('reports.ai', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_daily is not null and (p_daily < 0 or p_daily > 500) then
    return jsonb_build_object('error', 'bad-limit');
  end if;
  if v_scope = 'person' then
    v_name := 'Each colleague'; v_def := 10;
  elsif v_scope = 'admin' then
    v_name := 'Each admin'; v_def := 20;
  elsif v_scope = 'report' then
    v_name := 'Drafts per report, each colleague'; v_def := 1;
  elsif v_scope = 'report_admin' then
    v_name := 'Drafts per report, each admin'; v_def := 5;
  elsif v_scope = 'check' then
    v_name := 'Figures checks per report, each colleague'; v_def := 1;
  elsif v_scope = 'check_admin' then
    v_name := 'Figures checks per report, each admin'; v_def := 5;
  elsif v_scope = 'team' then
    return jsonb_build_object('error', 'bad-scope');
  else
    select * into t from public.team_members x where x.id::text = v_scope;
    if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
    v_name := t.name;
    v_def := case when coalesce(t.is_admin, false) or t.role = 'admin'
                  then public.ai_draft_limit('admin', 20) else public.ai_draft_limit('person', 10) end;
  end if;
  select l.daily into v_was from public.ai_draft_limits l where l.scope = v_scope;
  if v_was is not distinct from p_daily then return jsonb_build_object('ok', true, 'same', true); end if;
  select coalesce(x.name, x.email) into v_who from public.team_members x
   where lower(x.email) = lower(auth.jwt() ->> 'email') and x.active limit 1;
  insert into public.ai_draft_limits (scope, daily, set_by, set_at)
  values (v_scope, p_daily, v_who, now())
  on conflict (scope) do update set daily = excluded.daily, set_by = excluded.set_by, set_at = excluded.set_at;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_who, 'admin'), 'team.changed', 'AI',
          v_name || ': ' ||
          case when v_was is null then 'standard, ' || v_def || v_unit when v_was = 0 then 'stopped' else v_was || v_unit end ||
          ' → ' ||
          case when p_daily is null then 'standard, ' || v_def || v_unit when p_daily = 0 then 'stopped' else p_daily || v_unit end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.ai_draft_set_limit(text, integer) from public, anon, authenticated;
grant execute on function public.ai_draft_set_limit(text, integer) to authenticated;

do $$
begin
  if not exists (select 1 from pg_namespace where nspname = 'storage') then return; end if;
  if exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
              and policyname = 'handbook_files_add') then
    execute $p$alter policy handbook_files_add on storage.objects
      with check (bucket_id = 'handbook' and public.ops_granted('team.handbook', 'work'))$p$;
  end if;
  if exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
              and policyname = 'handbook_files_remove') then
    execute $p$alter policy handbook_files_remove on storage.objects
      using (bucket_id = 'handbook' and public.ops_granted('team.handbook', 'work'))$p$;
  end if;
end $$;

-- END OF ADMIN PARTS ----------------------------------------------------------
