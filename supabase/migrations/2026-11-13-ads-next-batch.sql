-- =====================================================================
-- ADS NEXT BATCH — suggestions for the next batch of creatives on an
-- Advertising Report
-- 2026-11-13, the user: "approve build both" (the mockup "Ads report ·
-- Next batch" of 2026-11-13). An Advertising Report gains a step, Next
-- batch, between Commentary and Check and submit: Write with AI reads the
-- report's ads (and, where Meta checks are on and the client links an ad
-- account, each ad's frequency, CTR, spend and results by day over the
-- period's last 14 days, from Meta) and suggests up to six things to make
-- next, each kept on the report as a draft field. One added to the
-- commentary is printed on a Next Batch page in the PDF while its switch is
-- on.
--
-- WHAT IT CHANGES
--   * `sm_reports.next_batch` (jsonb: when it was written, by whom, what it
--     read, the suggestions and which were added) and
--     `sm_reports.next_batch_print` (boolean, on by default). Both are the
--     report's own columns, so the draft-only guard (`sm_report_guard`)
--     holds them as it holds the commentary.
--   * `sm_report_snapshot` sends `next_batch`: the suggestions added, while
--     the switch is on, each its kind, creative, title, plan, reason and
--     points; nothing else of the suggestions leaves for the client. A
--     published version keeps them as it was published.
--   * The suggestions are an AI use of their own (`ai_drafts.purpose`
--     `next`, added by ADS NEXT BATCH, THE SQL EDITOR PART), 3 a person a
--     day by default (`ai_cap_default`), set on AI usage (Next batch).
--     `ai_next_claim(p_report)` counts a press before Claude is asked (Reports
--     at Work, an Advertising Report in draft the caller sees);
--     `ai_next_left(p_report)`. `ai_draft_usage` and `ai_draft_set_limit`
--     know the use.
--
-- ORDER: ADS NEXT BATCH, THE SQL EDITOR PART in the SQL Editor, then this
-- file, then the edge functions `meta-import` and `report-draft`, then the
-- pages. Safe to run twice.
--
-- ROLLBACK: pages first; drop ai_next_claim and ai_next_left; restate
-- ai_cap_default, ai_draft_set_limit and ai_draft_usage from PORTAL
-- ASSISTANT and sm_report_snapshot from its last band before this one. The
-- columns may stay.
-- =====================================================================
alter table public.sm_reports add column if not exists next_batch jsonb;
alter table public.sm_reports add column if not exists next_batch_print boolean not null default true;

create or replace function public.ai_cap_default(p_use text)
returns integer language sql immutable set search_path = public as $$
  select case p_use when 'drafts' then 10 when 'checks' then 10 when 'caption' then 20 when 'script' then 10 when 'picture' then 30
                    when 'analysis' then 3 when 'checklist' then 10 when 'analytics' then 3 when 'agent' then 30 when 'next' then 3
                    when 'per_report' then 1 else 0 end
$$;
revoke all on function public.ai_cap_default(text) from public, anon, authenticated;

/* A press of Write with AI on Next batch: counted before Claude is asked,
   under the drafts' one lock, against the colleague's own limit for it. */
create or replace function public.ai_next_claim(p_report uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  r public.sm_reports;
  since timestamptz := public.ai_draft_day();
  n_used integer;
  lim integer;
  new_id uuid;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports x where x.id = p_report;
  if r.id is null or not public.client_seen(r.client_id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if r.kind <> 'ads' then return jsonb_build_object('error', 'wrong-kind'); end if;
  if r.status <> 'draft' then return jsonb_build_object('error', 'not-draft'); end if;
  perform pg_advisory_xact_lock(hashtext('ai_draft_claim'));
  lim := public.ai_cap(m.id, 'next');
  if lim = 0 then return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0); end if;
  select count(*) into n_used from public.ai_drafts d
   where d.team_member_id = m.id and d.purpose = 'next' and d.created_at >= since and d.outcome <> 'failed';
  if n_used >= lim then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'next', 'limit', lim, 'next', since + interval '1 day');
  end if;
  insert into public.ai_drafts (report_id, team_member_id, client_id, kind, period_start, period_end, purpose, version_no)
  values (p_report, m.id, r.client_id, r.kind, r.period_start, r.period_end, 'next', r.version_no) returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', lim - n_used - 1, 'limit', lim);
end $$;
revoke all on function public.ai_next_claim(uuid) from public, anon;
grant execute on function public.ai_next_claim(uuid) to authenticated;

create or replace function public.ai_next_left(p_report uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  lim integer;
  l_left integer;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  lim := public.ai_cap(m.id, 'next');
  l_left := greatest(0, lim - (select count(*) from public.ai_drafts d
    where d.team_member_id = m.id and d.purpose = 'next' and d.created_at >= since and d.outcome <> 'failed')::integer);
  return jsonb_build_object('left', l_left, 'limit', lim, 'scope', case when lim = 0 then 'stopped' else 'next' end,
    'next', case when l_left > 0 or lim = 0 then null else since + interval '1 day' end);
end $$;
revoke all on function public.ai_next_left(uuid) from public, anon;
grant execute on function public.ai_next_left(uuid) to authenticated;

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
    "analysis":"Brand analyses","checklist":"Checklists","analytics":"Analytics analyses","agent":"Assistant","next":"Next batch"}';
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
  v_uses constant text[] := array['drafts', 'checks', 'caption', 'script', 'picture', 'analysis', 'checklist', 'analytics', 'agent', 'next'];
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
                                   'analysis', u.analysis, 'checklist', u.checklist, 'analytics', u.analytics, 'agent', u.agent, 'next', u.nxt),
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
                 count(*) filter (where d.purpose = 'agent') as agent,
                 count(*) filter (where d.purpose = 'next') as nxt
            from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed') u
       -- Every active colleague may ask the assistant (the user, 2026-11-13:
       -- "all colleagues"), so every one is offered a limit.
       where t.active
    ) s), '[]'::jsonb));
end $$;
revoke all on function public.ai_draft_usage() from public, anon, authenticated;
grant execute on function public.ai_draft_usage() to authenticated;

create or replace function public.sm_report_snapshot(p_id uuid, p_final boolean default false)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  r public.sm_reports;
  c public.clients;
begin
  if not public.allowed('reports', 'view') and not public.allowed('clients', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into r from public.sm_reports where id = p_id;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(r.client_id, 'view') then return jsonb_build_object('error', 'denied'); end if;
  -- Somebody who reads Clients but not Reports reads the finished report
  -- only: once it is confirmed, never while it is being prepared.
  if not public.allowed('reports', 'view') and r.status not in ('confirmed', 'published') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into c from public.clients where id = r.client_id;
  return jsonb_build_object(
    'report', jsonb_build_object(
      -- A white-label report names the brand it covers, with no client logo.
      'id', r.id, 'kind', r.kind, 'title', r.title, 'client_name', coalesce(r.brand_name, c.name),
      'client_logo_url', case when r.brand_name is null then c.logo_url end,
      'market', to_jsonb(c) ->> 'market', 'bill_market', public.client_bill_market(to_jsonb(c) ->> 'market', (to_jsonb(c) ->> 'bill_sgd')::boolean), 'lang', r.lang,
      'period_start', r.period_start, 'period_end', r.period_end,
      'headline', r.headline, 'intro', r.intro, 'insights', r.insights, 'rank_metric', r.rank_metric,
      'first_month', r.first_month, 'ads_totals', r.ads_totals,
      'status', case when p_final then 'final' else r.status end,
      'version_no', r.version_no, 'generated_at', now(),
      'prepared_by_name', (select name from public.team_members where id = r.submitted_by),
      -- The white-label client's wide logo while it is still ticked and the
      -- report's brand takes it (2026-10-07); else ADspace's own mark.
      'partner', (select jsonb_build_object('name', l.name, 'logo', l.report_logo)
                    from public.clients l where l.id = r.label_client and l.white_label
                     and coalesce((select b.logo from public.client_brands b where b.id = r.brand_id), 'partner') = 'partner'),
      -- The Next Batch page (2026-11-13): the suggestions added to the
      -- commentary, while its switch is on; nothing else of them.
      'next_batch', case when r.kind = 'ads' and r.next_batch_print and jsonb_typeof(r.next_batch -> 'items') = 'array' then
          (select jsonb_agg(jsonb_build_object('kind', i ->> 'kind', 'ad', i ->> 'ad', 'title', i ->> 'title',
                    'plan', i ->> 'plan', 'why', i ->> 'why', 'points', coalesce(i -> 'points', '[]'::jsonb)) order by e.n)
             from jsonb_array_elements(r.next_batch -> 'items') with ordinality e(i, n)
            where jsonb_typeof(i) = 'object' and coalesce(i ->> 'added', 'false') = 'true') end),
    'platforms', coalesce((select jsonb_agg(to_jsonb(p) - 'created_at' order by p.position, p.created_at)
                  from public.sm_report_platforms p where p.report_id = r.id), '[]'::jsonb),
    'posts', coalesce((select jsonb_agg((to_jsonb(q) - 'created_at' - 'thumb_data') || jsonb_build_object('thumb_url', q.thumb_data)
                  order by q.posted_on nulls last, q.position, q.created_at)
                  from public.sm_report_posts q where q.report_id = r.id), '[]'::jsonb),
    'ads', coalesce((select jsonb_agg((to_jsonb(a) - 'created_at' - 'thumb_data') || jsonb_build_object('thumb_url', a.thumb_data)
                  order by a.position, a.created_at)
                  from public.sm_report_ads a where a.report_id = r.id), '[]'::jsonb));
end $$;
grant execute on function public.sm_report_snapshot(uuid, boolean) to authenticated;

-- END OF ADS NEXT BATCH ----------------------------------------------

select public.functions_tidy();
