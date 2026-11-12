-- =====================================================================
-- PORTAL ASSISTANT
-- 2026-11-13, the user: "ok approve, all colleagues, build all phases"
-- (the Assistant mockup of 2026-11-13). Any active colleague asks in words
-- from the console's Ask panel; the page holds the conversation, reads the
-- records through the colleague's own sign-in, and every change waits on
-- the colleague's Confirm, made through the function the screen uses.
--
-- WHAT IT CHANGES
--   * The assistant is an AI use of its own (`ai_drafts.purpose` `agent`,
--     added by PORTAL ASSISTANT, THE SQL EDITOR PART): one row a question
--     asked, its tokens added up over every step Claude takes to answer it
--     (`agent_steps`, twelve at most). 30 a person a day by default
--     (`ai_cap_default`), set on AI usage (Assistant), every active
--     colleague listed there.
--   * `ai_agent_claim()` counts a question before Claude is asked (any
--     active colleague, `is_team()`); `ai_agent_left()`;
--     `ai_agent_turn(p_press)` lets a question take its next step (the
--     caller's own, under 30 minutes old, `too-many-steps` past twelve);
--     `ai_agent_tokens(p_press, p_in, p_out, p_model)` adds a step's tokens.
--   * `ai_draft_usage` and `ai_draft_set_limit` know the use.
--
-- ORDER: PORTAL ASSISTANT, THE SQL EDITOR PART in the SQL Editor (the
-- purpose and the Activity record's three tags), then this file, then the
-- edge function `portal-agent`, then the pages. Safe to run twice.
--
-- ROLLBACK: pages first; drop the four functions; restate ai_cap_default,
-- ai_draft_set_limit and ai_draft_usage from SCENE FRAMES DRAWN BY CLAUDE
-- and SCENE PICTURES. The column and the purpose may stay.
-- =====================================================================
alter table public.ai_drafts add column if not exists agent_steps integer not null default 0;

create or replace function public.ai_cap_default(p_use text)
returns integer language sql immutable set search_path = public as $$
  select case p_use when 'drafts' then 10 when 'checks' then 10 when 'caption' then 20 when 'script' then 10 when 'picture' then 30
                    when 'analysis' then 3 when 'checklist' then 10 when 'analytics' then 3 when 'agent' then 30 when 'per_report' then 1 else 0 end
$$;
revoke all on function public.ai_cap_default(text) from public, anon, authenticated;

/* A question asked of the assistant: counted before Claude is asked, under
   the drafts' one lock, against the colleague's own limit for it. */
create or replace function public.ai_agent_claim()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  n_used integer;
  lim integer;
  new_id uuid;
begin
  if not public.is_team() then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  perform pg_advisory_xact_lock(hashtext('ai_draft_claim'));
  lim := public.ai_cap(m.id, 'agent');
  if lim = 0 then return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0); end if;
  select count(*) into n_used from public.ai_drafts d
   where d.team_member_id = m.id and d.purpose = 'agent' and d.created_at >= since and d.outcome <> 'failed';
  if n_used >= lim then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'agent', 'limit', lim, 'next', since + interval '1 day');
  end if;
  insert into public.ai_drafts (team_member_id, purpose, agent_steps)
  values (m.id, 'agent', 1) returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', lim - n_used - 1, 'limit', lim);
end $$;
revoke all on function public.ai_agent_claim() from public, anon;
grant execute on function public.ai_agent_claim() to authenticated;

create or replace function public.ai_agent_left()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  lim integer;
  l_left integer;
begin
  if not public.is_team() then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  lim := public.ai_cap(m.id, 'agent');
  l_left := greatest(0, lim - (select count(*) from public.ai_drafts d
    where d.team_member_id = m.id and d.purpose = 'agent' and d.created_at >= since and d.outcome <> 'failed')::integer);
  return jsonb_build_object('left', l_left, 'limit', lim, 'scope', case when lim = 0 then 'stopped' else 'agent' end,
    'next', case when l_left > 0 or lim = 0 then null else since + interval '1 day' end);
end $$;
revoke all on function public.ai_agent_left() from public, anon;
grant execute on function public.ai_agent_left() to authenticated;

/* The next step of a question already counted: the caller's own, under
   half an hour old, twelve steps at most, so a loop of tool calls never
   runs on unpaid. */
create or replace function public.ai_agent_turn(p_press uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  m public.team_members := public.ops_me();
  d public.ai_drafts;
begin
  if m.id is null or not public.is_team() then return jsonb_build_object('error', 'denied'); end if;
  select * into d from public.ai_drafts x
   where x.id = p_press and x.team_member_id = m.id and x.purpose = 'agent' for update;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.created_at < now() - interval '30 minutes' then return jsonb_build_object('error', 'expired'); end if;
  if d.agent_steps >= 12 then return jsonb_build_object('error', 'too-many-steps'); end if;
  update public.ai_drafts x set agent_steps = x.agent_steps + 1 where x.id = d.id;
  return jsonb_build_object('ok', true, 'step', d.agent_steps + 1);
end $$;
revoke all on function public.ai_agent_turn(uuid) from public, anon;
grant execute on function public.ai_agent_turn(uuid) to authenticated;

/* A step's tokens, added to the question's (ai_draft_tokens keeps one
   call's alone). */
create or replace function public.ai_agent_tokens(p_press uuid, p_in integer, p_out integer, p_model text)
returns void language sql security definer set search_path = public as $$
  update public.ai_drafts d
     set input_tokens = coalesce(d.input_tokens, 0) + greatest(0, coalesce(p_in, 0)),
         output_tokens = coalesce(d.output_tokens, 0) + greatest(0, coalesce(p_out, 0)),
         model = left(nullif(btrim(coalesce(p_model, '')), ''), 80)
   where d.id = p_press and d.purpose = 'agent'
     and d.team_member_id = (public.ops_me()).id
$$;
revoke all on function public.ai_agent_tokens(uuid, integer, integer, text) from public, anon;
grant execute on function public.ai_agent_tokens(uuid, integer, integer, text) to authenticated;

create or replace function public.ai_draft_set_limit(p_scope text, p_daily integer)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_who text;
  v_name text;
  v_was integer;
  v_def integer;
  v_scope text := btrim(coalesce(p_scope, ''));
  v_use text;
  t public.team_members;
  v_words constant jsonb := '{"drafts":"Report drafts","checks":"Commentary checks","caption":"Captions","script":"Scripts","picture":"Scene pictures",
    "analysis":"Brand analyses","checklist":"Checklists","analytics":"Analytics analyses","agent":"Assistant"}';
begin
  if not public.ops_granted('reports.ai', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_daily is not null and (p_daily < 0 or p_daily > 500) then
    return jsonb_build_object('error', 'bad-limit');
  end if;
  if v_scope = 'per_report' then
    if p_daily is not null and p_daily > 1 then return jsonb_build_object('error', 'bad-limit'); end if;
    v_name := 'One draft and one check a report a day';
  elsif v_words ? v_scope then
    v_name := v_words ->> v_scope;
    v_def := public.ai_cap_default(v_scope);
  elsif v_scope ~ '^[0-9a-f-]{36}:[a-z]+$' and v_words ? split_part(v_scope, ':', 2) then
    v_use := split_part(v_scope, ':', 2);
    select * into t from public.team_members x where x.id::text = split_part(v_scope, ':', 1);
    if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
    v_name := (v_words ->> v_use) || ', ' || t.name;
    select l.daily into v_def from public.ai_draft_limits l where l.scope = v_use;
    v_def := coalesce(v_def, public.ai_cap(null, v_use));
  else
    return jsonb_build_object('error', 'bad-scope');
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
          case when v_scope = 'per_report' then case when coalesce(v_was, 1) = 0 then 'off' else 'on' end || ' → ' ||
                                                case when coalesce(p_daily, 1) = 0 then 'off' else 'on' end
               else case when v_was is null then 'standard, ' || v_def || ' a day' when v_was = 0 then 'stopped' else v_was || ' a day' end ||
                    ' → ' ||
                    case when p_daily is null then 'standard, ' || v_def || ' a day' when p_daily = 0 then 'stopped' else p_daily || ' a day' end
          end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.ai_draft_set_limit(text, integer) from public, anon, authenticated;
grant execute on function public.ai_draft_set_limit(text, integer) to authenticated;

create or replace function public.ai_draft_usage()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_day timestamptz := public.ai_draft_day();
  v_month timestamptz := now() - interval '30 days';
  -- This calendar month in Malaysia, for what the calls cost.
  v_cal timestamptz := date_trunc('month', now() at time zone 'Asia/Kuala_Lumpur') at time zone 'Asia/Kuala_Lumpur';
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_uses constant text[] := array['drafts', 'checks', 'caption', 'script', 'picture', 'analysis', 'checklist', 'analytics', 'agent'];
begin
  if not public.ops_granted('reports.ai', 'work') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object(
    'limits', (select jsonb_object_agg(u, public.ai_cap(null, u)) from unnest(v_uses || array['per_report']) u),
    'cost', (select jsonb_build_object(
        'since', v_cal,
        'price_in', public.app_setting('ai_price_in', v_today),
        'price_out', public.app_setting('ai_price_out', v_today),
        'price_search', coalesce(public.app_setting('ai_price_search', v_today), 10),
        'price_image', coalesce(public.app_setting('ai_price_image', v_today), 0.07),
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
                          + coalesce(d.web_searches, 0) * coalesce(public.app_setting('ai_price_search', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 10) / 1000.0
                          + case when d.purpose = 'picture' and coalesce(d.model, '') like 'gemini%' then coalesce(public.app_setting('ai_price_image', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 0.07) else 0 end as usd
                      from public.ai_drafts d where d.created_at >= v_cal and (d.outcome <> 'failed' or d.input_tokens is not null)) c2
             group by c2.purpose) p), '{}'::jsonb))
      from (select d.input_tokens, d.output_tokens, d.web_searches,
                   (coalesce(d.input_tokens, 0) * public.app_setting('ai_price_in', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)
                  + coalesce(d.output_tokens, 0) * public.app_setting('ai_price_out', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)) / 1000000.0
                  + coalesce(d.web_searches, 0) * coalesce(public.app_setting('ai_price_search', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 10) / 1000.0
                  + case when d.purpose = 'picture' and coalesce(d.model, '') like 'gemini%' then coalesce(public.app_setting('ai_price_image', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 0.07) else 0 end as usd
              from public.ai_drafts d where d.created_at >= v_cal and (d.outcome <> 'failed' or d.input_tokens is not null)) c),
    'resets_at', v_day + interval '1 day',
    'people', coalesce((select jsonb_agg(s.x order by s.x ->> 'name') from (
      select jsonb_build_object(
        'id', t.id, 'name', t.name, 'code', t.staff_code, 'group', g.name, 'group_slug', t.role,
        'admin', coalesce(t.is_admin, false) or t.role = 'admin',
        'used', jsonb_build_object('drafts', u.drafts, 'checks', u.checks, 'caption', u.caption, 'script', u.script, 'picture', u.picture,
                                   'analysis', u.analysis, 'checklist', u.checklist, 'analytics', u.analytics, 'agent', u.agent),
        'cap', (select jsonb_object_agg(k, public.ai_cap(t.id, k)) from unnest(v_uses) k),
        'own', coalesce((select jsonb_object_agg(split_part(l.scope, ':', 2), l.daily) from public.ai_draft_limits l
                          where l.scope like t.id::text || ':%' and l.daily is not null), '{}'::jsonb),
        'month', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_month and d.outcome <> 'failed')) as x
        from public.team_members t
        left join public.team_roles g on g.slug = t.role
        cross join lateral (
          select count(*) filter (where d.purpose = 'draft') as drafts, count(*) filter (where d.purpose = 'check') as checks,
                 count(*) filter (where d.purpose = 'caption') as caption, count(*) filter (where d.purpose = 'script') as script,
                 count(*) filter (where d.purpose = 'picture') as picture,
                 count(*) filter (where d.purpose = 'analysis') as analysis, count(*) filter (where d.purpose = 'checklist') as checklist,
                 count(*) filter (where d.purpose = 'analytics') as analytics,
                 count(*) filter (where d.purpose = 'agent') as agent
            from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed') u
       -- Every active colleague may ask the assistant (the user, 2026-11-13:
       -- "all colleagues"), so every one is offered a limit.
       where t.active
    ) s), '[]'::jsonb));
end $$;
revoke all on function public.ai_draft_usage() from public, anon, authenticated;
grant execute on function public.ai_draft_usage() to authenticated;

-- END OF PORTAL ASSISTANT ----------------------------------------------

select public.functions_tidy();
