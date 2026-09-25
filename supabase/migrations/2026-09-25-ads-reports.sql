-- 2026-09-25 · Social media advertising reports
--
-- Run once in the Supabase SQL editor, after 2026-09-25-social-media-reports.sql.
-- Safe to run twice: every statement is `add column if not exists`, `create
-- ... if not exists`, `create or replace`, or a policy or trigger dropped
-- before it is made. Mirrored in supabase/schema.sql (the section under the
-- banner below), compared byte for byte by tests/smsql.js.

-- =========================================================================
-- SOCIAL MEDIA ADVERTISING REPORTS
--
-- The second kind the report builder makes: a client's monthly paid social
-- report, from the team's two templates (a first month, and every month
-- after it). Same engine of steps as the social media report (draft,
-- review, confirmed, published), same versions and the same client portal;
-- what differs is what is entered and how the PDF is drawn (js/smreport.js).
--
--   sm_reports.first_month  The client's first month of ads. Set when the
--                           report is made (no earlier advertising report
--                           for the client) and the team's to change. A
--                           first month carries the reading guidance and
--                           no previous period; a later month compares
--                           against the one before.
--   sm_reports.ads_totals   The account's own figures for the period, which
--                           cannot be added up from the ads (reach counts a
--                           person once however many ads they saw), and the
--                           previous period's, carried forward from the last
--                           advertising report when a new one is made:
--                           { reach, impressions, spend,
--                             prev_start, prev_end, prev_reach,
--                             prev_impressions, prev_spend,
--                             prev_groups: { objective: { results, spend } },
--                             groups: { objective: { results, label } } }
--   sm_report_ads           One row an ad and objective: the same creative
--                           run under two goals is two rows, compared side by
--                           side in the PDF.
--
-- Rollback:
--   drop table if exists public.sm_report_ads;
--   alter table public.sm_reports drop column if exists first_month,
--     drop column if exists ads_totals;
--   and re-run sm_report_create, sm_report_submit and sm_report_snapshot from
--   2026-09-25-social-media-reports.sql.
-- =========================================================================

alter table public.sm_reports add column if not exists first_month boolean not null default false;
alter table public.sm_reports add column if not exists ads_totals jsonb not null default '{}'::jsonb;

create table if not exists public.sm_report_ads (
  id            uuid primary key default gen_random_uuid(),
  report_id     uuid not null references public.sm_reports(id) on delete cascade,
  position      integer not null default 0,
  name          text not null,
  objective     text not null default 'awareness',
  result_label  text,
  audience      text,
  starts_on     date,
  ends_on       date,
  spend         numeric(12, 2),
  results       bigint,
  reach         bigint,
  impressions   bigint,
  ctr           numeric(8, 4),
  -- The cost per result as Ads Manager prints it, where it was typed; the PDF
  -- works it out from spend and results otherwise. `thousand` is a figure
  -- per 1,000 people reached, as Ads Manager prices a reach result.
  cpr           numeric(12, 4),
  cpr_basis     text,
  -- The share of results by age band, in per cent: {"18-24": 0, "25-34": 47.6, ...}.
  age           jsonb not null default '{}'::jsonb,
  hook_rate     numeric(8, 4),
  hold_rate     numeric(8, 4),
  -- Average play time, in seconds.
  avg_play      numeric(8, 2),
  -- Plays reaching each quarter of the video, in per cent of plays:
  -- {"p25": 40, "p50": 22, "p75": 12, "p95": 7, "p100": 5}.
  retention     jsonb not null default '{}'::jsonb,
  thumb_data    text,
  remark        text,
  created_at    timestamptz not null default now(),
  constraint sm_ads_basis check (cpr_basis is null or cpr_basis in ('result', 'thousand')),
  constraint sm_ads_objective check (objective in ('awareness', 'traffic', 'engagement', 'leads', 'messaging', 'sales', 'app')),
  constraint sm_ads_name check (btrim(name) <> ''),
  constraint sm_ads_dates check (starts_on is null or ends_on is null or ends_on >= starts_on),
  constraint sm_ads_figures check (coalesce(spend, 0) >= 0 and coalesce(results, 0) >= 0
                                   and coalesce(reach, 0) >= 0 and coalesce(impressions, 0) >= 0),
  constraint sm_ads_thumb check (thumb_data is null or (thumb_data like 'data:image/%' and length(thumb_data) <= 300000))
);
create index if not exists sm_report_ads_report_idx on public.sm_report_ads (report_id, position);

alter table public.sm_report_ads enable row level security;
drop policy if exists sm_ads_all on public.sm_report_ads;
create policy sm_ads_all on public.sm_report_ads for all to authenticated
  using (public.allowed('clients.reports', 'view')) with check (public.allowed('clients.reports', 'work'));
drop trigger if exists sm_ads_guard on public.sm_report_ads;
create trigger sm_ads_guard before insert or update or delete on public.sm_report_ads
  for each row execute function public.sm_report_child_guard();

/* The whole report as js/smreport.js reads it. `p_final` is the published
   form: the status the PDF prints as issued, and the time it was issued.
   The client's market is read through jsonb, because it decides which
   taxes the spend note names and a database without the column still draws
   the report. */
create or replace function public.sm_report_snapshot(p_id uuid, p_final boolean default false)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  r public.sm_reports;
  c public.clients;
begin
  if not public.allowed('clients.reports', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.clients where id = r.client_id;
  return jsonb_build_object(
    'report', jsonb_build_object(
      'id', r.id, 'kind', r.kind, 'title', r.title, 'client_name', c.name, 'client_logo_url', c.logo_url,
      'market', to_jsonb(c) ->> 'market',
      'period_start', r.period_start, 'period_end', r.period_end,
      'headline', r.headline, 'intro', r.intro, 'insights', r.insights, 'rank_metric', r.rank_metric,
      'first_month', r.first_month, 'ads_totals', r.ads_totals,
      'status', case when p_final then 'final' else r.status end,
      'version_no', r.version_no, 'generated_at', now(),
      'prepared_by_name', (select name from public.team_members where id = r.submitted_by)),
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

/* A new report of a kind for a client and a period.
   Social: the accounts of the client's latest earlier social report are
   carried forward, each starting with the followers that report ended on.
   Advertising: the first one a client has is their first month; a later one
   carries the previous report's period and totals forward as the figures it
   is compared against, so a month opens with its comparison in place. */
create or replace function public.sm_report_create(p_client uuid, p_start date, p_end date, p_kind text default 'social')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  rid uuid;
  prev uuid;
  pr public.sm_reports;
  totals jsonb := '{}'::jsonb;
  pgroups jsonb;
begin
  if me.id is null or not public.allowed('clients.reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_client is null or not exists (select 1 from public.clients where id = p_client) then
    return jsonb_build_object('error', 'not-found');
  end if;
  if p_start is null or p_end is null or p_end < p_start then return jsonb_build_object('error', 'bad-period'); end if;
  if coalesce(p_kind, '') not in ('social', 'ads') then return jsonb_build_object('error', 'bad-kind'); end if;
  select id into rid from public.sm_reports
   where client_id = p_client and kind = p_kind and period_start = p_start and period_end = p_end;
  if rid is not null then return jsonb_build_object('error', 'exists', 'id', rid); end if;
  select id into prev from public.sm_reports
   where client_id = p_client and kind = p_kind and period_start < p_start
   order by period_start desc limit 1;
  perform set_config('adspace.sm_fn', 'on', true);
  if p_kind = 'ads' then
    if prev is not null then
      select * into pr from public.sm_reports where id = prev;
      select coalesce(jsonb_object_agg(g.objective, jsonb_build_object('results',
               coalesce(nullif(pr.ads_totals #>> array['groups', g.objective, 'results'], '')::numeric, g.results),
               'spend', g.spend)), '{}'::jsonb)
        into pgroups
        from (select a.objective, sum(a.results) as results, sum(a.spend) as spend
                from public.sm_report_ads a where a.report_id = prev group by a.objective) g;
      totals := jsonb_strip_nulls(jsonb_build_object(
        'prev_start', pr.period_start, 'prev_end', pr.period_end,
        'prev_reach', nullif(pr.ads_totals ->> 'reach', '')::numeric,
        'prev_impressions', coalesce(nullif(pr.ads_totals ->> 'impressions', '')::numeric,
                                     (select sum(impressions) from public.sm_report_ads where report_id = prev)),
        'prev_spend', coalesce(nullif(pr.ads_totals ->> 'spend', '')::numeric,
                               (select sum(spend) from public.sm_report_ads where report_id = prev)),
        'prev_groups', pgroups));
    end if;
    insert into public.sm_reports (client_id, kind, title, period_start, period_end, created_by, first_month, ads_totals)
    values (p_client, p_kind, 'Social Media Advertising Report', p_start, p_end, me.id, prev is null, totals)
    returning id into rid;
  else
    insert into public.sm_reports (client_id, kind, period_start, period_end, created_by)
    values (p_client, p_kind, p_start, p_end, me.id) returning id into rid;
    if prev is not null then
      insert into public.sm_report_platforms (report_id, platform, account_name, handle, group_key, group_label,
        position, metrics, followers_start, er_basis, metric_notes)
      select rid, p.platform, p.account_name, p.handle, p.group_key, p.group_label, p.position, p.metrics,
             coalesce(p.followers_end, case when p.followers_start is not null and p.growth_override is not null
                                            then p.followers_start + p.growth_override end),
             p.er_basis, p.metric_notes
        from public.sm_report_platforms p where p.report_id = prev;
    end if;
  end if;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(rid, 'report.created');
  return jsonb_build_object('ok', true, 'id', rid, 'carried', prev is not null);
end $$;
grant execute on function public.sm_report_create(uuid, date, date, text) to authenticated;

/* Submit for review: a social report needs its accounts and posts, an
   advertising report its ads. */
create or replace function public.sm_report_submit(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
begin
  if me.id is null or not public.allowed('clients.reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'draft' then return jsonb_build_object('error', 'not-draft', 'status', r.status); end if;
  if r.kind = 'ads' then
    if not exists (select 1 from public.sm_report_ads where report_id = p_id) then
      return jsonb_build_object('error', 'no-ads');
    end if;
  else
    if not exists (select 1 from public.sm_report_platforms where report_id = p_id) then
      return jsonb_build_object('error', 'no-platforms');
    end if;
    if not exists (select 1 from public.sm_report_posts where report_id = p_id) then
      return jsonb_build_object('error', 'no-posts');
    end if;
  end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set status = 'review', submitted_by = me.id, submitted_at = now(),
    return_note = null, confirmed_by = null, confirmed_at = null where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.submitted');
  return jsonb_build_object('ok', true, 'status', 'review');
end $$;
grant execute on function public.sm_report_submit(uuid) to authenticated;
-- END OF SOCIAL MEDIA ADVERTISING REPORTS
