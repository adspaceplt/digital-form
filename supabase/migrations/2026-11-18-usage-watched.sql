-- ===========================================================================
-- USAGE AND LIMITS WATCHED (2026-11-18)
-- ===========================================================================
-- WHY: the user, 2026-11-18: "the more important checks would be the usage,
-- the limits, the charges that could incurred". What the portal spends is
-- read in one place, each month against the last, and the admins are told
-- before a plan's limit is reached, never after.
--
-- WHAT IT CHANGES
--   * `usage_report(p_month)` (Business settings at View): the month's use
--     against the month before: the database's size against the plan
--     (`plan_db_mb`, 500, the Free plan) and its five largest tables, AI
--     runs, tokens and estimated US$ (priced as AI usage prices them), emails
--     sent (clients, creators, suppliers, the portal's own), WhatsApp
--     messages, and the last S3 report's files and bytes. A month ahead of
--     this one, or none, is this month.
--   * `usage_watch(p_now)` (pg_cron `usage-watch`, 09:13 MYT daily; no page
--     calls it): on the 1st, each active admin is told last month's use
--     (kind `usage.month`); any day the database passes `plan_db_alert_pct`
--     (80) of the plan, each is told once a month (kind `usage.limit`).
--   * Settings `plan_db_mb` and `plan_db_alert_pct`, seeded once.
--
-- ORDER: this file (connector), then the page (Settings: Usage). An open page
-- calls nothing new until it is refreshed. Safe to run twice.
--
-- ROLLBACK: drop function usage_report(date), usage_watch(timestamptz);
-- select cron.unschedule('usage-watch'); delete the two settings.
-- ===========================================================================

insert into public.app_settings (key, from_date, value)
select k.key, date '2023-08-14', k.value
  from (values ('plan_db_mb', 500), ('plan_db_alert_pct', 80)) k(key, value)
 where not exists (select 1 from public.app_settings s where s.key = k.key);

create or replace function public.usage_month_of(p_from date, p_to date)
returns jsonb
language sql stable security definer set search_path = public as $$
  /* One month's use, Malaysia's days [p_from, p_to). */
  with a as (
    select count(*) as runs, coalesce(sum(d.input_tokens), 0) as tin, coalesce(sum(d.output_tokens), 0) as tout,
           coalesce(sum((coalesce(d.input_tokens, 0) * coalesce(public.app_setting('ai_price_in', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 0)
                       + coalesce(d.output_tokens, 0) * coalesce(public.app_setting('ai_price_out', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 0)) / 1000000.0
                       + coalesce(d.web_searches, 0) * coalesce(public.app_setting('ai_price_search', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 10) / 1000.0
                       + case when d.purpose = 'picture' and coalesce(d.model, '') like 'gemini%'
                              then coalesce(public.app_setting('ai_price_image', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 0.07) else 0 end), 0) as usd
      from public.ai_drafts d
     where d.created_at >= p_from::timestamp at time zone 'Asia/Kuala_Lumpur'
       and d.created_at < p_to::timestamp at time zone 'Asia/Kuala_Lumpur'
  ), m as (
    select (select count(*) from public.client_emails e where e.created_at >= p_from::timestamp at time zone 'Asia/Kuala_Lumpur' and e.created_at < p_to::timestamp at time zone 'Asia/Kuala_Lumpur')
         + (select count(*) from public.creator_emails e where e.created_at >= p_from::timestamp at time zone 'Asia/Kuala_Lumpur' and e.created_at < p_to::timestamp at time zone 'Asia/Kuala_Lumpur')
         + (select count(*) from public.supplier_emails e where e.created_at >= p_from::timestamp at time zone 'Asia/Kuala_Lumpur' and e.created_at < p_to::timestamp at time zone 'Asia/Kuala_Lumpur')
         + (select count(*) from public.system_emails e where e.created_at >= p_from::timestamp at time zone 'Asia/Kuala_Lumpur' and e.created_at < p_to::timestamp at time zone 'Asia/Kuala_Lumpur') as emails,
           (select count(*) from public.wa_outbox w where w.created_at >= p_from::timestamp at time zone 'Asia/Kuala_Lumpur' and w.created_at < p_to::timestamp at time zone 'Asia/Kuala_Lumpur') as whatsapp
  )
  select jsonb_build_object('ai_runs', a.runs, 'ai_tokens_in', a.tin, 'ai_tokens_out', a.tout, 'ai_usd', round(a.usd::numeric, 2),
                            'emails', m.emails, 'whatsapp', m.whatsapp)
    from a, m
$$;
revoke all on function public.usage_month_of(date, date) from public, anon, authenticated;

create or replace function public.usage_report(p_month date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_m date;
  v_size bigint := pg_database_size(current_database());
  v_limit numeric;
begin
  if not public.ops_granted('team.settings', 'view') then return jsonb_build_object('error', 'denied'); end if;
  v_m := date_trunc('month', least(coalesce(p_month, v_today), v_today))::date;
  v_limit := coalesce(public.app_setting('plan_db_mb', v_today), 500);
  return jsonb_build_object(
    'month', v_m,
    'this', public.usage_month_of(v_m, least((v_m + interval '1 month')::date, v_today + 1)),
    'last', public.usage_month_of((v_m - interval '1 month')::date, v_m),
    'db', jsonb_build_object('bytes', v_size, 'limit_mb', v_limit,
            'alert_pct', coalesce(public.app_setting('plan_db_alert_pct', v_today), 80),
            'pct', round(v_size / (v_limit * 1048576.0) * 100, 1),
            'tables', coalesce((select jsonb_agg(jsonb_build_object('name', t.relname, 'bytes', t.b) order by t.b desc)
                                  from (select c.relname, pg_total_relation_size(c.oid) as b
                                          from pg_class c join pg_namespace n on n.oid = c.relnamespace
                                         where n.nspname = 'public' and c.relkind = 'r'
                                         order by 2 desc limit 5) t), '[]'::jsonb)),
    's3', (select jsonb_build_object('ran_at', s.ran_at, 'files', s.listed, 'bytes', s.listed_bytes)
             from public.s3_sweeps s where coalesce(s.failed, 0) = 0 and s.listed is not null
            order by s.ran_at desc limit 1));
end $$;
grant execute on function public.usage_report(date) to authenticated;

create or replace function public.usage_watch(p_now timestamptz default now())
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_today date := (p_now at time zone 'Asia/Kuala_Lumpur')::date;
  v_m date := date_trunc('month', v_today)::date;
  v_last jsonb;
  v_size bigint := pg_database_size(current_database());
  v_limit numeric := coalesce(public.app_setting('plan_db_mb', v_today), 500);
  v_alert numeric := coalesce(public.app_setting('plan_db_alert_pct', v_today), 80);
  v_pct numeric;
  v_told int := 0;
  v_n int;
  v_words text;
begin
  v_pct := round(v_size / (v_limit * 1048576.0) * 100, 1);
  if extract(day from v_today) = 1 then
    v_last := public.usage_month_of((v_m - interval '1 month')::date, v_m);
    v_words := concat_ws(' · ',
      'Database ' || round(v_size / 1048576.0) || ' MB of ' || v_limit || ' MB',
      'AI ' || (v_last ->> 'ai_runs') || case when (v_last ->> 'ai_runs')::int = 1 then ' run' else ' runs' end
            || ', about US$ ' || to_char((v_last ->> 'ai_usd')::numeric, 'FM999,990.00'),
      (v_last ->> 'emails') || case when (v_last ->> 'emails')::int = 1 then ' email' else ' emails' end,
      (v_last ->> 'whatsapp') || ' WhatsApp') || '.';
    insert into public.ops_notifications (team_member_id, kind, title, body, dedupe_key)
    select t.id, 'usage.month', 'Usage for ' || (array['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sept','Oct','Nov','Dec'])[extract(month from (v_m - interval '1 month'))::int] || ' ' || extract(year from (v_m - interval '1 month'))::int, v_words,
           'usage.month.' || to_char(v_m, 'YYYY-MM') || '.' || t.id
      from public.team_members t
     where t.active and t.is_admin
    on conflict (dedupe_key) do nothing;
    get diagnostics v_n = row_count; v_told := v_told + v_n;
  end if;
  if v_pct >= v_alert then
    insert into public.ops_notifications (team_member_id, kind, title, body, dedupe_key)
    select t.id, 'usage.limit', 'Database near its limit',
           'The database holds ' || round(v_size / 1048576.0) || ' MB of the plan''s ' || v_limit || ' MB (' || v_pct || '%).',
           'usage.limit.' || to_char(v_m, 'YYYY-MM') || '.' || t.id
      from public.team_members t
     where t.active and t.is_admin
    on conflict (dedupe_key) do nothing;
    get diagnostics v_n = row_count; v_told := v_told + v_n;
  end if;
  return jsonb_build_object('db_pct', v_pct, 'told', v_told);
end $$;
revoke all on function public.usage_watch(timestamptz) from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: usage is not watched until it is.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'usage-watch';
  perform cron.schedule('usage-watch', '13 1 * * *', 'select public.usage_watch()');
end $$;

-- END OF USAGE AND LIMITS WATCHED --------------------------------------------

select public.functions_tidy();
