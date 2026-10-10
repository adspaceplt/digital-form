-- ===========================================================================
-- BRAND ANALYSIS — an AI analysis of a client's brand on its Brand pane:
-- positioning, target audiences, SWOT, content and ad targeting, read from
-- the client's own record, reports, post results, Meta where linked, and
-- detailed web research on the brand and its competitors.
-- 2026-10-10. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. Runs after SCRIPT WRITER, META CHECKS SWITCH, CLIENT BRIEF and the
-- WhatsApp approval reminder's settings.
--
-- WHAT CHANGED (the user, 2026-10-10: "provide a suggestions or inputs on the
-- deep analysis of this clients … brand part, target audiences, SWOTs,
-- advantages disadvantages, ads targetting etc."; "clients name just give
-- the clients brand name, perform detailed web research"; "anyone could run
-- it")
--   1. `brand_analyses` (RLS on, no policy, no grant): a client's analyses,
--      one row a run, numbered by client; read and written only through the
--      functions below. Not in CLIENT SCOPE's guarded list: a colleague at
--      Clients View runs one, so each function asks `client_seen` at View
--      itself.
--   2. `ai_analysis_claim(p_client)` / `ai_analysis_left()`: Clients View on
--      a client the colleague sees. Counted by the colleague a day, from
--      midnight MYT: `analysis` (3) a colleague's, `analysis_admin` (10) an
--      admin's, settings in `ai_draft_limits`; 0 stops it.
--   3. `brand_analysis_save(...)`: the `brand-analysis` function keeps what
--      it wrote as the caller, against the caller's own pending press; filed
--      `client.brand`.
--   4. `brand_analyses_list(p_client)`: every version, newest first (20 at
--      most), with who ran and who confirmed it. `brand_analysis_confirm(
--      p_id, p_on)`: the declaration that it was read and confirmed, and its
--      way back; filed `client.brand`.
--   5. `brand_analysis_brief(p_client)`: the latest confirmed analysis's
--      positioning, audiences and pillars in compact form, for Write with AI
--      on captions, scripts and reports (a colleague on the team who sees
--      the client).
--   6. `ai_drafts.web_searches` and `ai_draft_searches(p_id, p_n)`: the web
--      searches a press made, priced at `ai_price_search` (10, US$ a
--      thousand searches), a Business setting from a day like the token
--      prices; `app_settings_set` takes it.
--   7. `ai_draft_usage()` adds the analysis limits, each colleague's
--      analyses today, the searches and their cost; `ai_draft_set_limit`
--      names `analysis` and `analysis_admin`.
--
-- ROLLBACK
--   Run SCRIPT WRITER's ai_draft_usage and ai_draft_set_limit and WHATSAPP
--   APPROVAL REMINDER's app_settings_set again; then, in the SQL Editor, drop
--   the functions above and the table, delete the analysis rows from ai_drafts
--   and put the purpose check back to ('draft', 'check', 'caption',
--   'script'). The column and the setting's row may stay.
-- ===========================================================================

create table if not exists public.brand_analyses (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  version integer not null,
  analysis jsonb not null,
  sources jsonb not null default '[]'::jsonb,
  basis jsonb not null default '{}'::jsonb,
  hypothesis boolean not null default false,
  model text,
  press_id uuid,
  created_by uuid references public.team_members(id) on delete set null,
  created_at timestamptz not null default now(),
  confirmed_by uuid references public.team_members(id) on delete set null,
  confirmed_at timestamptz,
  unique (client_id, version),
  constraint brand_analyses_shape check (jsonb_typeof(analysis) = 'object' and char_length(analysis::text) <= 60000
    and jsonb_typeof(sources) = 'array' and char_length(sources::text) <= 12000)
);
alter table public.brand_analyses enable row level security;
revoke all on table public.brand_analyses from public, anon, authenticated;

alter table public.ai_drafts add column if not exists web_searches integer;
alter table public.ai_drafts drop constraint if exists ai_drafts_purpose;
alter table public.ai_drafts add constraint ai_drafts_purpose check (purpose in ('draft', 'check', 'caption', 'script', 'analysis'));

insert into public.app_settings (key, from_date, value)
select 'ai_price_search', date '2026-10-10', 10
 where not exists (select 1 from public.app_settings s where s.key = 'ai_price_search');

-- An analysis: the colleague's own count a day, apart from every other AI use.
create or replace function public.ai_analysis_claim(p_client uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  n_used integer;
  lim integer;
  new_id uuid;
begin
  if not public.allowed('clients', 'view') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  if not exists (select 1 from public.clients c where c.id = p_client) then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(p_client, 'view') then return jsonb_build_object('error', 'client-scope'); end if;
  -- One count at a time, with the drafts, so the last analysis is taken once.
  perform pg_advisory_xact_lock(hashtext('ai_draft_claim'));
  lim := case when coalesce(m.is_admin, false) or m.role = 'admin'
              then public.ai_draft_limit('analysis_admin', 10) else public.ai_draft_limit('analysis', 3) end;
  if lim = 0 then return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0); end if;
  select count(*) into n_used from public.ai_drafts d
   where d.team_member_id = m.id and d.purpose = 'analysis' and d.created_at >= since and d.outcome <> 'failed';
  if n_used >= lim then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'analysis', 'limit', lim, 'next', since + interval '1 day');
  end if;
  insert into public.ai_drafts (team_member_id, client_id, purpose)
  values (m.id, p_client, 'analysis') returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', lim - n_used - 1, 'limit', lim);
end $$;

-- What Run analysis has left today, read without writing.
create or replace function public.ai_analysis_left()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  lim integer;
  l_left integer;
begin
  if not public.allowed('clients', 'view') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  lim := case when coalesce(m.is_admin, false) or m.role = 'admin'
              then public.ai_draft_limit('analysis_admin', 10) else public.ai_draft_limit('analysis', 3) end;
  l_left := greatest(0, lim - (select count(*) from public.ai_drafts d
    where d.team_member_id = m.id and d.purpose = 'analysis' and d.created_at >= since and d.outcome <> 'failed')::integer);
  return jsonb_build_object('left', l_left, 'limit', lim, 'scope', case when lim = 0 then 'stopped' else 'analysis' end,
    'next', case when l_left > 0 or lim = 0 then null else since + interval '1 day' end);
end $$;

-- The web searches a press made, on the caller's own row, once.
create or replace function public.ai_draft_searches(p_id uuid, p_n integer)
returns void
language sql security definer set search_path = public as $$
  update public.ai_drafts d
     set web_searches = greatest(0, least(coalesce(p_n, 0), 100))
   where d.id = p_id and d.web_searches is null
     and d.team_member_id = (public.ops_me()).id
$$;

-- One version a row, with who ran and who confirmed it.
create or replace function public.brand_analysis_row(a public.brand_analyses)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', a.id, 'client_id', a.client_id, 'version', a.version, 'analysis', a.analysis,
    'sources', a.sources, 'basis', a.basis, 'hypothesis', a.hypothesis, 'created_at', a.created_at,
    'by', (select t.name from public.team_members t where t.id = a.created_by),
    'confirmed_at', a.confirmed_at,
    'confirmed_by', (select t.name from public.team_members t where t.id = a.confirmed_by))
$$;
revoke all on function public.brand_analysis_row(public.brand_analyses) from public, anon, authenticated;

-- What the brand-analysis function wrote, kept against the caller's own
-- pending press for this client.
create or replace function public.brand_analysis_save(p_press uuid, p_analysis jsonb, p_sources jsonb,
                                                      p_basis jsonb, p_hypothesis boolean, p_model text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  d public.ai_drafts;
  c public.clients;
  a public.brand_analyses;
  v_no integer;
begin
  if not public.allowed('clients', 'view') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into d from public.ai_drafts x where x.id = p_press for update;
  if d.id is null or d.team_member_id <> m.id or d.purpose <> 'analysis' or d.outcome <> 'pending'
     or exists (select 1 from public.brand_analyses x where x.press_id = d.id) then
    return jsonb_build_object('error', 'not-found');
  end if;
  select * into c from public.clients x where x.id = d.client_id;
  if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(c.id, 'view') then return jsonb_build_object('error', 'client-scope'); end if;
  if jsonb_typeof(p_analysis) is distinct from 'object' or char_length(p_analysis::text) > 60000 then
    return jsonb_build_object('error', 'bad-analysis');
  end if;
  perform pg_advisory_xact_lock(hashtext('brand_analysis:' || c.id::text));
  select coalesce(max(x.version), 0) + 1 into v_no from public.brand_analyses x where x.client_id = c.id;
  insert into public.brand_analyses (client_id, version, analysis, sources, basis, hypothesis, model, press_id, created_by)
  values (c.id, v_no, p_analysis,
          case when jsonb_typeof(p_sources) = 'array' and char_length(p_sources::text) <= 12000 then p_sources else '[]'::jsonb end,
          case when jsonb_typeof(p_basis) = 'object' then p_basis else '{}'::jsonb end,
          coalesce(p_hypothesis, false), left(nullif(btrim(coalesce(p_model, '')), ''), 80), d.id, m.id)
  returning * into a;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, m.email), 'client.brand', c.name,
          'Brand analysis: version ' || v_no || ' run with AI' ||
          case when coalesce(p_hypothesis, false) then ', a starting hypothesis to test' else '' end);
  return public.brand_analysis_row(a);
end $$;

create or replace function public.brand_analyses_list(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.allowed('clients', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if not public.client_seen(p_client, 'view') then return jsonb_build_object('error', 'client-scope'); end if;
  return jsonb_build_object('versions', coalesce((select jsonb_agg(public.brand_analysis_row(x) order by x.version desc)
    from (select * from public.brand_analyses a where a.client_id = p_client order by a.version desc limit 20) x), '[]'::jsonb));
end $$;

-- The declaration that a colleague read the analysis and confirms it; with
-- p_on false, its way back.
create or replace function public.brand_analysis_confirm(p_id uuid, p_on boolean default true)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  a public.brand_analyses;
  c public.clients;
begin
  if not public.allowed('clients', 'view') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into a from public.brand_analyses x where x.id = p_id for update;
  if a.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(a.client_id, 'view') then return jsonb_build_object('error', 'client-scope'); end if;
  select * into c from public.clients x where x.id = a.client_id;
  if coalesce(p_on, true) = (a.confirmed_at is not null) then return public.brand_analysis_row(a); end if;
  update public.brand_analyses x
     set confirmed_at = case when coalesce(p_on, true) then now() end,
         confirmed_by = case when coalesce(p_on, true) then m.id end
   where x.id = p_id returning * into a;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, m.email), 'client.brand', c.name,
          'Brand analysis: version ' || a.version ||
          case when coalesce(p_on, true) then ' written with AI, read and confirmed' else ' confirmation withdrawn' end);
  return public.brand_analysis_row(a);
end $$;

-- For Write with AI: the latest confirmed analysis, in compact form.
create or replace function public.brand_analysis_brief(p_client uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_team() and public.client_seen(p_client, 'view') then (
    select jsonb_strip_nulls(jsonb_build_object(
      'positioning', a.analysis -> 'positioning',
      'audiences', (select jsonb_agg(jsonb_build_object('name', s ->> 'name', 'pains', s ->> 'pains', 'motivations', s ->> 'motivations'))
                      from jsonb_array_elements(case when jsonb_typeof(a.analysis -> 'audiences') = 'array' then a.analysis -> 'audiences' else '[]'::jsonb end) s),
      'pillars', a.analysis #> '{content,pillars}',
      'hypothesis', case when a.hypothesis then true end))
      from public.brand_analyses a
     where a.client_id = p_client and a.confirmed_at is not null
     order by a.version desc limit 1) end
$$;

revoke all on function public.ai_analysis_claim(uuid) from public, anon, authenticated;
revoke all on function public.ai_analysis_left() from public, anon, authenticated;
revoke all on function public.ai_draft_searches(uuid, integer) from public, anon, authenticated;
revoke all on function public.brand_analysis_save(uuid, jsonb, jsonb, jsonb, boolean, text) from public, anon, authenticated;
revoke all on function public.brand_analyses_list(uuid) from public, anon, authenticated;
revoke all on function public.brand_analysis_confirm(uuid, boolean) from public, anon, authenticated;
revoke all on function public.brand_analysis_brief(uuid) from public, anon, authenticated;
grant execute on function public.ai_analysis_claim(uuid) to authenticated;
grant execute on function public.ai_analysis_left() to authenticated;
grant execute on function public.ai_draft_searches(uuid, integer) to authenticated;
grant execute on function public.brand_analysis_save(uuid, jsonb, jsonb, jsonb, boolean, text) to authenticated;
grant execute on function public.brand_analyses_list(uuid) to authenticated;
grant execute on function public.brand_analysis_confirm(uuid, boolean) to authenticated;
grant execute on function public.brand_analysis_brief(uuid) to authenticated;

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
    'script', public.ai_draft_limit('script', 10),
    'script_admin', public.ai_draft_limit('script_admin', 20),
    'analysis', public.ai_draft_limit('analysis', 3),
    'analysis_admin', public.ai_draft_limit('analysis_admin', 10),
    'cost', (select jsonb_build_object(
        'since', v_cal,
        'price_in', public.app_setting('ai_price_in', v_today),
        'price_out', public.app_setting('ai_price_out', v_today),
        'price_search', coalesce(public.app_setting('ai_price_search', v_today), 10),
        'uses', count(*),
        'untracked', count(*) filter (where c.input_tokens is null),
        'input', coalesce(sum(c.input_tokens), 0),
        'output', coalesce(sum(c.output_tokens), 0),
        'searches', coalesce(sum(c.web_searches), 0),
        'usd', round(coalesce(sum(c.usd), 0), 2),
        'by', coalesce((select jsonb_object_agg(p.purpose, p.x) from (
            select c2.purpose, jsonb_build_object('uses', count(*), 'input', coalesce(sum(c2.input_tokens), 0),
                     'output', coalesce(sum(c2.output_tokens), 0), 'searches', coalesce(sum(c2.web_searches), 0),
                     'usd', round(coalesce(sum(c2.usd), 0), 2)) as x
              from (select d.purpose, d.input_tokens, d.output_tokens, d.web_searches,
                           (coalesce(d.input_tokens, 0) * public.app_setting('ai_price_in', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)
                          + coalesce(d.output_tokens, 0) * public.app_setting('ai_price_out', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)) / 1000000.0
                          + coalesce(d.web_searches, 0) * coalesce(public.app_setting('ai_price_search', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 10) / 1000.0 as usd
                      from public.ai_drafts d where d.created_at >= v_cal and (d.outcome <> 'failed' or d.input_tokens is not null)) c2
             group by c2.purpose) p), '{}'::jsonb))
      from (select d.input_tokens, d.output_tokens, d.web_searches,
                   (coalesce(d.input_tokens, 0) * public.app_setting('ai_price_in', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)
                  + coalesce(d.output_tokens, 0) * public.app_setting('ai_price_out', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)) / 1000000.0
                  + coalesce(d.web_searches, 0) * coalesce(public.app_setting('ai_price_search', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 10) / 1000.0 as usd
              from public.ai_drafts d where d.created_at >= v_cal and (d.outcome <> 'failed' or d.input_tokens is not null)) c),
    'resets_at', v_day + interval '1 day',
    'people', coalesce((select jsonb_agg(s.x order by s.x ->> 'name') from (
      select jsonb_build_object(
        'id', t.id, 'name', t.name, 'code', t.staff_code, 'group', g.name, 'group_slug', t.role,
        'admin', coalesce(t.is_admin, false) or t.role = 'admin',
        'day', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed' and d.purpose in ('draft', 'check')),
        'captions', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed' and d.purpose = 'caption'),
        'caption_cap', case when coalesce(t.is_admin, false) or t.role = 'admin'
                            then public.ai_draft_limit('caption_admin', 40) else public.ai_draft_limit('caption', 20) end,
        'scripts', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed' and d.purpose = 'script'),
        'script_cap', case when coalesce(t.is_admin, false) or t.role = 'admin'
                           then public.ai_draft_limit('script_admin', 20) else public.ai_draft_limit('script', 10) end,
        'analyses', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed' and d.purpose = 'analysis'),
        'analysis_cap', case when coalesce(t.is_admin, false) or t.role = 'admin'
                             then public.ai_draft_limit('analysis_admin', 10) else public.ai_draft_limit('analysis', 3) end,
        'month', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_month and d.outcome <> 'failed'),
        'limit', (select l.daily from public.ai_draft_limits l where l.scope = t.id::text),
        'cap', public.ai_day_cap(t)) as x
        from public.team_members t
        left join public.team_roles g on g.slug = t.role
       where t.active
         and (coalesce(t.is_admin, false) or t.role = 'admin'
              or public.level_rank(coalesce(t.access ->> 'reports', 'none')) >= public.level_rank('work')
              or public.level_rank(coalesce(t.access ->> 'review', 'none')) >= public.level_rank('work')
              or public.level_rank(coalesce(t.access ->> 'scripts', 'none')) >= public.level_rank('work')
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
  elsif v_scope = 'script' then
    v_name := 'Scripts, each colleague'; v_def := 10;
  elsif v_scope = 'script_admin' then
    v_name := 'Scripts, each admin'; v_def := 20;
  elsif v_scope = 'analysis' then
    v_name := 'Brand analyses, each colleague'; v_def := 3;
  elsif v_scope = 'analysis_admin' then
    v_name := 'Brand analyses, each admin'; v_def := 10;
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

create or replace function public.app_settings_set(p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members; v_k text; v_v numeric; v_was numeric; v_name text; v_unit text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_keys constant text[] := array['lead_followup_hours', 'proposal_followup_days', 'sst_pct',
    'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_24', 'report_due_days', 'revision_due_days',
    'ai_price_in', 'ai_price_out', 'meta_checks', 'approval_reminder_days', 'ai_price_search'];
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
       or (v_k = 'approval_reminder_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'sst_pct' and (v_v < 0 or v_v > 100))
       or (v_k like 'term_%' and (v_v < -100 or v_v > 100))
       or (v_k like 'ai_price_%' and (v_v < 0 or v_v > 1000))
       or (v_k = 'meta_checks' and v_v not in (0, 1)) then
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
        when 'ai_price_out' then 'AI output, a million tokens' when 'ai_price_search' then 'AI web searches, a thousand' when 'meta_checks' then 'Meta checks'
        when 'approval_reminder_days' then 'Approval reminder' else 'Report due' end;
      v_unit := case when v_k = 'lead_followup_hours' then ' hours' when v_k in ('proposal_followup_days', 'report_due_days', 'revision_due_days', 'approval_reminder_days') then ' days'
        else '%' end;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(v_me.name, 'admin'), 'team.changed', 'Settings',
              v_name || ': ' || case when v_k = 'meta_checks' then
                case when v_was = 1 then 'On' else 'Off' end || ' → ' || case when v_v = 1 then 'On' else 'Off' end ||
                ' · from ' || public.register_day(p_from) else '' end ||
              case when v_k = 'meta_checks' then '' else case when v_k like 'ai_price_%' then 'US$' else '' end ||
              trim(to_char(v_was, 'FM999999990.99'), '.') || case when v_k like 'ai_price_%' then '' else v_unit end || ' → ' ||
              case when v_k like 'ai_price_%' then 'US$' else '' end ||
              trim(to_char(v_v, 'FM999999990.99'), '.') || case when v_k like 'ai_price_%' then '' else v_unit end ||
              ' · from ' || public.register_day(p_from) end);
      v_moved := v_moved || v_k;
    end if;
  end loop;
  return public.app_settings_read() || jsonb_build_object('changed', to_jsonb(v_moved));
end $$;
revoke all on function public.app_settings_set(date, jsonb) from public, anon;

-- END OF BRAND ANALYSIS -------------------------------------------------------

select public.functions_tidy();
