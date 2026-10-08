-- ===========================================================================
-- CAPTION WRITER AND AI COST — Write caption in Content Review, counted apart
-- from the reports' AI uses, and every AI call's tokens kept with an
-- estimated cost a month.
-- 2026-10-08. Safe to run twice. Rollback below. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/smsql.js compares the two.
--
-- WHAT CHANGED (the user, 2026-10-08: "1 2 ok", "Also check costing")
--   1. `ai_drafts.purpose` takes `caption`; a caption's row names its set
--      (`batch_id`) and client. Every row keeps what the call cost:
--      `input_tokens`, `output_tokens` and `model`.
--   2. `ai_caption_claim(p_batch)`: Content Review: Sets at Work, a set on a
--      client the colleague sees. Counted by the colleague a day, from
--      midnight MYT: `caption` (20) a colleague's, `caption_admin` (40) an
--      admin's, both settings in `ai_draft_limits`; 0 stops it.
--      `ai_caption_left()` reads what is left without writing.
--   3. Captions never take from the reports' limits: `ai_draft_claim`,
--      `ai_draft_left`, `ai_check_claim` and `ai_check_left` count the day's
--      uses without them.
--   4. `ai_draft_tokens(p_id, p_in, p_out, p_model)`: the edge function
--      records the call's tokens on its own row, once, drafted or failed.
--   5. `ai_price_in` (4) and `ai_price_out` (20), US$ a million tokens, are
--      Business settings from a day on (`app_settings_set`).
--   6. `ai_draft_usage()` adds the caption limits, each colleague's captions
--      today, and this month's tokens and estimated cost by purpose, each
--      row priced at the prices of its own day.
--   7. `ai_draft_set_limit` names `caption` and `caption_admin`.
--
-- ROLLBACK
--   Run the AI LIMITS A COLLEAGUE A REPORT A DAY section and the latest
--   app_settings_set, ai_draft_usage and ai_draft_set_limit (ADMIN PARTS)
--   again; then, in the SQL Editor, drop ai_caption_claim(uuid),
--   ai_caption_left() and ai_draft_tokens(uuid, integer, integer, text),
--   delete the caption rows from ai_drafts and put the purpose check back to
--   ('draft', 'check'). The columns and the price settings may stay.
-- ===========================================================================

alter table public.ai_drafts add column if not exists batch_id uuid;
alter table public.ai_drafts add column if not exists input_tokens integer;
alter table public.ai_drafts add column if not exists output_tokens integer;
alter table public.ai_drafts add column if not exists model text;
alter table public.ai_drafts drop constraint if exists ai_drafts_purpose;
alter table public.ai_drafts add constraint ai_drafts_purpose check (purpose in ('draft', 'check', 'caption'));
create index if not exists ai_drafts_purpose_idx on public.ai_drafts (team_member_id, purpose, created_at);

insert into public.app_settings (key, from_date, value)
select k.key, date '2026-10-08', k.value
  from (values ('ai_price_in', 4), ('ai_price_out', 20)) k(key, value)
 where not exists (select 1 from public.app_settings s where s.key = k.key);

create or replace function public.app_settings_set(p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members; v_k text; v_v numeric; v_was numeric; v_name text; v_unit text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_keys constant text[] := array['lead_followup_hours', 'proposal_followup_days', 'sst_pct',
    'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_24', 'report_due_days', 'revision_due_days',
    'ai_price_in', 'ai_price_out'];
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
       or (v_k like 'term_%' and (v_v < -100 or v_v > 100))
       or (v_k like 'ai_price_%' and (v_v < 0 or v_v > 1000)) then
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
        when 'revision_due_days' then 'Revision due' when 'ai_price_in' then 'AI input, a million tokens'
        when 'ai_price_out' then 'AI output, a million tokens' else 'Report due' end;
      v_unit := case when v_k = 'lead_followup_hours' then ' hours' when v_k in ('proposal_followup_days', 'report_due_days', 'revision_due_days') then ' days'
        else '%' end;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(v_me.name, 'admin'), 'team.changed', 'Settings',
              v_name || ': ' || case when v_k like 'ai_price_%' then 'US$' else '' end ||
              trim(to_char(v_was, 'FM999999990.99'), '.') || case when v_k like 'ai_price_%' then '' else v_unit end || ' → ' ||
              case when v_k like 'ai_price_%' then 'US$' else '' end ||
              trim(to_char(v_v, 'FM999999990.99'), '.') || case when v_k like 'ai_price_%' then '' else v_unit end ||
              ' · from ' || public.register_day(p_from));
      v_moved := v_moved || v_k;
    end if;
  end loop;
  return public.app_settings_read() || jsonb_build_object('changed', to_jsonb(v_moved));
end $$;
revoke all on function public.app_settings_set(date, jsonb) from public, anon;

-- A caption: the colleague's own count a day, apart from the reports'.
create or replace function public.ai_caption_claim(p_batch uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  b public.batches;
  since timestamptz := public.ai_draft_day();
  n_cap integer;
  lim integer;
  new_id uuid;
begin
  if not public.allowed('review.sets', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into b from public.batches x where x.id = p_batch;
  if b.id is null or not public.client_seen(b.client_id, 'view') then
    return jsonb_build_object('error', 'not-found');
  end if;
  -- One count at a time, with the drafts, so the last caption is taken once.
  perform pg_advisory_xact_lock(hashtext('ai_draft_claim'));
  lim := case when coalesce(m.is_admin, false) or m.role = 'admin'
              then public.ai_draft_limit('caption_admin', 40) else public.ai_draft_limit('caption', 20) end;
  if lim = 0 then return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0); end if;
  select count(*) into n_cap from public.ai_drafts d
   where d.team_member_id = m.id and d.purpose = 'caption' and d.created_at >= since and d.outcome <> 'failed';
  if n_cap >= lim then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'caption', 'limit', lim, 'next', since + interval '1 day');
  end if;
  insert into public.ai_drafts (team_member_id, client_id, batch_id, purpose)
  values (m.id, b.client_id, b.id, 'caption') returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', lim - n_cap - 1, 'limit', lim);
end $$;

-- What Write caption has left today, read without writing.
create or replace function public.ai_caption_left()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  lim integer;
  l_left integer;
begin
  if not public.allowed('review.sets', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  lim := case when coalesce(m.is_admin, false) or m.role = 'admin'
              then public.ai_draft_limit('caption_admin', 40) else public.ai_draft_limit('caption', 20) end;
  l_left := greatest(0, lim - (select count(*) from public.ai_drafts d
    where d.team_member_id = m.id and d.purpose = 'caption' and d.created_at >= since and d.outcome <> 'failed')::integer);
  return jsonb_build_object('left', l_left, 'limit', lim, 'scope', case when lim = 0 then 'stopped' else 'caption' end,
    'next', case when l_left > 0 or lim = 0 then null else since + interval '1 day' end);
end $$;

-- What a call cost, on the caller's own row, once.
create or replace function public.ai_draft_tokens(p_id uuid, p_in integer, p_out integer, p_model text)
returns void
language sql security definer set search_path = public as $$
  update public.ai_drafts d
     set input_tokens = greatest(0, coalesce(p_in, 0)),
         output_tokens = greatest(0, coalesce(p_out, 0)),
         model = left(nullif(btrim(coalesce(p_model, '')), ''), 80)
   where d.id = p_id and d.input_tokens is null
     and d.team_member_id = (public.ops_me()).id
$$;

revoke all on function public.ai_caption_claim(uuid) from public, anon, authenticated;
revoke all on function public.ai_caption_left() from public, anon, authenticated;
revoke all on function public.ai_draft_tokens(uuid, integer, integer, text) from public, anon, authenticated;
grant execute on function public.ai_caption_claim(uuid) to authenticated;
grant execute on function public.ai_caption_left() to authenticated;
grant execute on function public.ai_draft_tokens(uuid, integer, integer, text) to authenticated;

create or replace function public.ai_draft_claim(p_report uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  r public.sm_reports;
  since timestamptz := public.ai_draft_day();
  n_report integer;
  n_member integer;
  lim_member integer;
  lim_report integer;
  new_id uuid;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  -- One count at a time, so two presses together cannot both take the last draft.
  perform pg_advisory_xact_lock(hashtext('ai_draft_claim'));
  select * into r from public.sm_reports where id = p_report;
  lim_member := public.ai_day_cap(m);
  if lim_member = 0 then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0);
  end if;
  lim_report := case when coalesce(m.is_admin, false) then public.ai_draft_limit('report_admin', 5)
                     else public.ai_draft_limit('report', 1) end;
  select count(*) into n_report from public.ai_draft_same(p_report) s
   where s.team_member_id = m.id and s.created_at >= since;
  if n_report >= lim_report then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'report', 'limit', lim_report, 'next', since + interval '1 day');
  end if;
  select count(*) into n_member from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed' and d.purpose <> 'caption';
  if n_member >= lim_member then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'person', 'limit', lim_member, 'next', since + interval '1 day');
  end if;
  insert into public.ai_drafts (report_id, team_member_id, client_id, kind, period_start, period_end, version_no)
  values (p_report, m.id, r.client_id, r.kind, r.period_start, r.period_end, r.version_no) returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', lim_member - n_member - 1);
end $$;

create or replace function public.ai_draft_left(p_report uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  is_adm boolean;
  n_member integer;
  l_report integer; l_member integer; l_min integer;
  lim_member integer;
  lim_report integer;
  v_scope text;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  is_adm := coalesce(m.is_admin, false);
  lim_member := public.ai_day_cap(m);
  lim_report := case when is_adm then public.ai_draft_limit('report_admin', 5) else public.ai_draft_limit('report', 1) end;
  l_report := greatest(0, lim_report - (select count(*) from public.ai_draft_same(p_report) s
    where s.team_member_id = m.id and s.created_at >= since)::integer);
  select count(*) into n_member from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed' and d.purpose <> 'caption';
  l_member := greatest(0, lim_member - n_member);
  l_min := least(l_report, l_member);
  v_scope := case when lim_member = 0 then 'stopped' when l_min = l_report then 'report' else 'person' end;
  return jsonb_build_object(
    'left', l_min, 'scope', v_scope,
    'limit', case v_scope when 'stopped' then 0 when 'report' then lim_report else lim_member end,
    'report', l_report, 'person', l_member, 'admin', is_adm,
    'next', case when l_min > 0 or v_scope = 'stopped' then null else since + interval '1 day' end);
end $$;

create or replace function public.ai_check_claim(p_report uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  r public.sm_reports;
  since timestamptz := public.ai_draft_day();
  n_member integer;
  lim_member integer;
  lim_check integer;
  new_id uuid;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_report;
  if r.id is null or not public.client_seen(r.client_id, 'view') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if r.status not in ('draft', 'review') then return jsonb_build_object('error', 'not-open'); end if;
  -- One count at a time, with the drafts, so the last use is taken once.
  perform pg_advisory_xact_lock(hashtext('ai_draft_claim'));
  lim_member := public.ai_day_cap(m);
  if lim_member = 0 then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0);
  end if;
  lim_check := case when coalesce(m.is_admin, false) then public.ai_draft_limit('check_admin', 5)
                    else public.ai_draft_limit('check', 1) end;
  if (select count(*) from public.ai_drafts d
       where d.report_id = p_report and d.purpose = 'check' and d.outcome <> 'failed'
         and d.team_member_id = m.id and d.created_at >= since) >= lim_check then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'report_check', 'limit', lim_check, 'next', since + interval '1 day');
  end if;
  select count(*) into n_member from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed' and d.purpose <> 'caption';
  if n_member >= lim_member then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'person', 'limit', lim_member, 'next', since + interval '1 day');
  end if;
  insert into public.ai_drafts (report_id, team_member_id, client_id, kind, period_start, period_end, purpose, version_no)
  values (p_report, m.id, r.client_id, r.kind, r.period_start, r.period_end, 'check', r.version_no) returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', lim_member - n_member - 1);
end $$;

create or replace function public.ai_check_left(p_report uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  r public.sm_reports;
  since timestamptz := public.ai_draft_day();
  is_adm boolean;
  n_member integer;
  l_report integer; l_member integer; l_min integer;
  lim_member integer;
  lim_check integer;
  v_scope text;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_report;
  if r.id is null or not public.client_seen(r.client_id, 'view') then
    return jsonb_build_object('error', 'not-found');
  end if;
  is_adm := coalesce(m.is_admin, false);
  lim_member := public.ai_day_cap(m);
  lim_check := case when is_adm then public.ai_draft_limit('check_admin', 5) else public.ai_draft_limit('check', 1) end;
  l_report := greatest(0, lim_check - (select count(*) from public.ai_drafts d
    where d.report_id = p_report and d.purpose = 'check' and d.outcome <> 'failed'
      and d.team_member_id = m.id and d.created_at >= since)::integer);
  select count(*) into n_member from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed' and d.purpose <> 'caption';
  l_member := greatest(0, lim_member - n_member);
  l_min := least(l_report, l_member);
  v_scope := case when lim_member = 0 then 'stopped' when l_min = l_report then 'report_check' else 'person' end;
  return jsonb_build_object(
    'left', l_min, 'scope', v_scope, 'version', r.version_no,
    'limit', case v_scope when 'stopped' then 0 when 'report_check' then lim_check else lim_member end,
    'report', l_report, 'person', l_member, 'admin', is_adm,
    'next', case when l_min > 0 or v_scope = 'stopped' then null else since + interval '1 day' end);
end $$;

revoke all on function public.ai_draft_claim(uuid) from public, anon, authenticated;
revoke all on function public.ai_draft_left(uuid) from public, anon, authenticated;
revoke all on function public.ai_check_claim(uuid) from public, anon, authenticated;
revoke all on function public.ai_check_left(uuid) from public, anon, authenticated;
grant execute on function public.ai_draft_claim(uuid) to authenticated;
grant execute on function public.ai_draft_left(uuid) to authenticated;
grant execute on function public.ai_check_claim(uuid) to authenticated;
grant execute on function public.ai_check_left(uuid) to authenticated;

create or replace function public.ai_draft_usage()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_day timestamptz := public.ai_draft_day();
  v_month timestamptz := now() - interval '30 days';
  -- This calendar month in Malaysia, for what the calls cost.
  v_cal timestamptz := date_trunc('month', now() at time zone 'Asia/Kuala_Lumpur') at time zone 'Asia/Kuala_Lumpur';
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  if not public.ops_granted('reports.ai', 'work') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object(
    'person', public.ai_draft_limit('person', 10),
    'admin', public.ai_draft_limit('admin', 20),
    'report', public.ai_draft_limit('report', 1),
    'report_admin', public.ai_draft_limit('report_admin', 5),
    'check', public.ai_draft_limit('check', 1),
    'check_admin', public.ai_draft_limit('check_admin', 5),
    'caption', public.ai_draft_limit('caption', 20),
    'caption_admin', public.ai_draft_limit('caption_admin', 40),
    'cost', (select jsonb_build_object(
        'since', v_cal,
        'price_in', public.app_setting('ai_price_in', v_today),
        'price_out', public.app_setting('ai_price_out', v_today),
        'uses', count(*),
        'untracked', count(*) filter (where c.input_tokens is null),
        'input', coalesce(sum(c.input_tokens), 0),
        'output', coalesce(sum(c.output_tokens), 0),
        'usd', round(coalesce(sum(c.usd), 0), 2),
        'by', coalesce((select jsonb_object_agg(p.purpose, p.x) from (
            select c2.purpose, jsonb_build_object('uses', count(*), 'input', coalesce(sum(c2.input_tokens), 0),
                     'output', coalesce(sum(c2.output_tokens), 0), 'usd', round(coalesce(sum(c2.usd), 0), 2)) as x
              from (select d.purpose, d.input_tokens, d.output_tokens,
                           (coalesce(d.input_tokens, 0) * public.app_setting('ai_price_in', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)
                          + coalesce(d.output_tokens, 0) * public.app_setting('ai_price_out', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)) / 1000000.0 as usd
                      from public.ai_drafts d where d.created_at >= v_cal and (d.outcome <> 'failed' or d.input_tokens is not null)) c2
             group by c2.purpose) p), '{}'::jsonb))
      from (select d.input_tokens, d.output_tokens,
                   (coalesce(d.input_tokens, 0) * public.app_setting('ai_price_in', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)
                  + coalesce(d.output_tokens, 0) * public.app_setting('ai_price_out', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)) / 1000000.0 as usd
              from public.ai_drafts d where d.created_at >= v_cal and (d.outcome <> 'failed' or d.input_tokens is not null)) c),
    'resets_at', v_day + interval '1 day',
    'people', coalesce((select jsonb_agg(s.x order by s.x ->> 'name') from (
      select jsonb_build_object(
        'id', t.id, 'name', t.name, 'code', t.staff_code, 'group', g.name, 'group_slug', t.role,
        'admin', coalesce(t.is_admin, false) or t.role = 'admin',
        'day', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed' and d.purpose <> 'caption'),
        'captions', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed' and d.purpose = 'caption'),
        'caption_cap', case when coalesce(t.is_admin, false) or t.role = 'admin'
                            then public.ai_draft_limit('caption_admin', 40) else public.ai_draft_limit('caption', 20) end,
        'month', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_month and d.outcome <> 'failed'),
        'limit', (select l.daily from public.ai_draft_limits l where l.scope = t.id::text),
        'cap', public.ai_day_cap(t)) as x
        from public.team_members t
        left join public.team_roles g on g.slug = t.role
       where t.active
         and (coalesce(t.is_admin, false) or t.role = 'admin'
              or public.level_rank(coalesce(t.access ->> 'reports', 'none')) >= public.level_rank('work')
              or public.level_rank(coalesce(t.access ->> 'review', 'none')) >= public.level_rank('work')
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
  elsif v_scope = 'caption' then
    v_name := 'Captions, each colleague'; v_def := 20;
  elsif v_scope = 'caption_admin' then
    v_name := 'Captions, each admin'; v_def := 40;
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

-- END OF CAPTION WRITER AND AI COST -----------------------------------------

select public.functions_tidy();
