-- 2026-09-25 · The report builder: advertising reports, and Reports as a section
--
-- Run once in the Supabase SQL editor, after 2026-09-25-social-media-reports.sql.
-- Safe to run twice: every statement is `add column if not exists`, `create
-- ... if not exists`, `create or replace`, a policy or trigger dropped before
-- it is made, or an update guarded on the key it moves. Mirrored in
-- supabase/schema.sql (the two sections under the banners below), compared
-- byte for byte by tests/smsql.js.
--
-- Two things:
--   1. The second kind the builder makes, the social media advertising report.
--   2. Reports become a section of the access ladder of their own (`reports`),
--      no longer a part of Clients, so a colleague can prepare reports
--      without reading client records. A group's level moves across once.
--      Anybody who reads Clients still reads a client's finished reports
--      (confirmed or published) on the client record, through two functions
--      that answer the finished ones only.

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
  using (public.allowed('reports', 'view')) with check (public.allowed('reports', 'work'));
drop trigger if exists sm_ads_guard on public.sm_report_ads;
create trigger sm_ads_guard before insert or update or delete on public.sm_report_ads
  for each row execute function public.sm_report_child_guard();

/* The whole report as js/smreport.js reads it. `p_final` is the published
   form: the status the PDF prints as issued, and the time it was issued.
   The client's market is read through jsonb, because it decides which
   taxes the spend note names and a database without the column still draws
   the report. Reports View reads any report; Clients View reads a finished
   one, which is what the client record's Reports tab shows. */
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
  -- Somebody who reads Clients but not Reports reads the finished report
  -- only: once it is confirmed, never while it is being prepared.
  if not public.allowed('reports', 'view') and r.status not in ('confirmed', 'published') then
    return jsonb_build_object('error', 'denied');
  end if;
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
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
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
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
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

-- =========================================================================
-- THE REPORTS SECTION
--
-- Reports were a part of Clients (`clients.reports`), so a colleague who
-- prepared reports had to be able to read every client record, and the
-- report opened on the client's record. They are a section of their own now:
--
--   reports View    read every report, preview its PDF
--   reports Work    start a report, enter its figures and text, submit it,
--                   revise a published one
--   reports Manage  also confirm, return, publish, unpublish and delete
--
-- A group's level moves across once: its `clients.reports` level where it
-- set one, else its Clients level (which the part fell back to), `none`
-- included, and the old key goes. Guarded on the new key, so a re-run moves
-- nothing. The client record keeps a Reports tab that shows the finished
-- reports only, read by anybody who reads Clients through the two functions
-- at the foot of this section; the tables themselves answer Reports alone.
--
-- Rollback:
--   update public.team_roles set access = (access - 'reports')
--     || jsonb_build_object('clients.reports', access ->> 'reports') where access ? 'reports';
--   drop function if exists public.sm_client_reports(uuid);
--   drop function if exists public.sm_report_file(uuid);
--   and re-run the policies and functions of 2026-09-25-social-media-reports.sql.
-- =========================================================================

update public.team_roles
   set access = (access - 'clients.reports')
       || jsonb_build_object('reports', coalesce(access ->> 'clients.reports', access ->> 'clients', 'none'))
 where not (access ? 'reports');
update public.team_members
   set access = (access - 'clients.reports')
       || jsonb_build_object('reports', coalesce(access ->> 'clients.reports', access ->> 'clients', 'none'))
 where not (access ? 'reports');

drop policy if exists sm_reports_read on public.sm_reports;
create policy sm_reports_read on public.sm_reports for select to authenticated
  using (public.allowed('reports', 'view'));
drop policy if exists sm_reports_write on public.sm_reports;
create policy sm_reports_write on public.sm_reports for update to authenticated
  using (public.allowed('reports', 'work')) with check (public.allowed('reports', 'work'));
drop policy if exists sm_platforms_all on public.sm_report_platforms;
create policy sm_platforms_all on public.sm_report_platforms for all to authenticated
  using (public.allowed('reports', 'view')) with check (public.allowed('reports', 'work'));
drop policy if exists sm_posts_all on public.sm_report_posts;
create policy sm_posts_all on public.sm_report_posts for all to authenticated
  using (public.allowed('reports', 'view')) with check (public.allowed('reports', 'work'));
drop policy if exists sm_versions_read on public.sm_report_versions;
create policy sm_versions_read on public.sm_report_versions for select to authenticated
  using (public.allowed('reports', 'view'));

-- A report is started for a client from the Reports section, so the client
-- list is read there too.
drop policy if exists clients_read on public.clients;
create policy clients_read on public.clients for select to authenticated
  using (public.allowed('clients', 'view') or public.allowed('review', 'view')
      or public.allowed('campaigns', 'view') or public.allowed('reports', 'view'));

/* Back to draft with a note saying what to change. The person who
   submitted it may take it back while it waits; otherwise it is the
   reviewer's act, which is Manage. */
create or replace function public.sm_report_return(p_id uuid, p_note text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status not in ('review', 'confirmed') then return jsonb_build_object('error', 'not-returnable', 'status', r.status); end if;
  if not public.allowed('reports', 'manage')
     and not (r.status = 'review' and r.submitted_by = me.id) then
    return jsonb_build_object('error', 'denied');
  end if;
  if coalesce(btrim(p_note), '') = '' then return jsonb_build_object('error', 'note-required'); end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set status = 'draft', return_note = btrim(p_note),
    confirmed_by = null, confirmed_at = null where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.returned', btrim(p_note));
  return jsonb_build_object('ok', true, 'status', 'draft');
end $$;
grant execute on function public.sm_report_return(uuid, text) to authenticated;

/* The internal confirmation: somebody who may manage reports, and never
   the person who submitted it, reads it and says it is right. */
create or replace function public.sm_report_confirm(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
begin
  if me.id is null or not public.allowed('reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'review' then return jsonb_build_object('error', 'not-in-review', 'status', r.status); end if;
  if r.submitted_by = me.id then return jsonb_build_object('error', 'self-confirm'); end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set status = 'confirmed', confirmed_by = me.id, confirmed_at = now() where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.confirmed');
  return jsonb_build_object('ok', true, 'status', 'confirmed');
end $$;
grant execute on function public.sm_report_confirm(uuid) to authenticated;

/* Publish: the confirmed report is frozen as its version and the client
   can read it. The same press twice publishes once. */
create or replace function public.sm_report_publish(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  snap jsonb;
  vid uuid;
begin
  if me.id is null or not public.allowed('reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status = 'published' then
    select id into vid from public.sm_report_versions where report_id = p_id and version_no = r.version_no;
    return jsonb_build_object('ok', true, 'status', 'published', 'version_id', vid, 'again', true);
  end if;
  if r.status <> 'confirmed' then return jsonb_build_object('error', 'not-confirmed', 'status', r.status); end if;
  snap := public.sm_report_snapshot(p_id, true);
  perform set_config('adspace.sm_fn', 'on', true);
  insert into public.sm_report_versions (report_id, version_no, snapshot, published_by)
  values (p_id, r.version_no, snap, me.name)
  on conflict (report_id, version_no) do update
    set snapshot = excluded.snapshot, published_by = excluded.published_by, published_at = now(),
        withdrawn_at = null, withdrawn_by = null, withdraw_reason = null
  returning id into vid;
  update public.sm_reports set status = 'published' where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.published');
  return jsonb_build_object('ok', true, 'status', 'published', 'version_id', vid);
end $$;
grant execute on function public.sm_report_publish(uuid) to authenticated;

/* Revise a published report: a new draft with the next version number.
   The client goes on reading the published version until the revision is
   published in its place. */
create or replace function public.sm_report_revise(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'published' then return jsonb_build_object('error', 'not-published', 'status', r.status); end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set status = 'draft', version_no = r.version_no + 1, return_note = null,
    submitted_by = null, submitted_at = null, confirmed_by = null, confirmed_at = null where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.revised');
  return jsonb_build_object('ok', true, 'status', 'draft', 'version_no', r.version_no + 1);
end $$;
grant execute on function public.sm_report_revise(uuid) to authenticated;

/* Take the published version off the client's portal, with a reason. The
   version is kept, marked withdrawn; a published report goes back to
   confirmed so it can be published again. */
create or replace function public.sm_report_unpublish(p_id uuid, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  n int;
begin
  if me.id is null or not public.allowed('reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_report_versions set withdrawn_at = now(), withdrawn_by = me.name, withdraw_reason = btrim(p_reason)
   where report_id = p_id and withdrawn_at is null;
  get diagnostics n = row_count;
  if n = 0 then
    perform set_config('adspace.sm_fn', 'off', true);
    return jsonb_build_object('error', 'not-published');
  end if;
  if r.status = 'published' then
    update public.sm_reports set status = 'confirmed' where id = p_id;
  end if;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.unpublished', btrim(p_reason));
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.sm_report_unpublish(uuid, text) to authenticated;

/* A report that was never published may be deleted, with its period typed
   back. One that a client has read is not: unpublish it instead, so the
   record of what the client was shown stands. */
create or replace function public.sm_report_delete(p_id uuid, p_confirm text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  word text;
  cname text;
begin
  if me.id is null or not public.allowed('reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if exists (select 1 from public.sm_report_versions where report_id = p_id) then
    return jsonb_build_object('error', 'has-versions');
  end if;
  word := public.sm_period_word(r.period_start, r.period_end);
  if lower(btrim(coalesce(p_confirm, ''))) <> lower(word) then return jsonb_build_object('error', 'confirm-mismatch'); end if;
  select name into cname from public.clients where id = r.client_id;
  perform set_config('adspace.sm_fn', 'on', true);
  delete from public.sm_reports where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'report.deleted', cname, word || ' · v' || r.version_no);
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.sm_report_delete(uuid, text) to authenticated;

/* The client record's Reports tab: a client's finished reports, for
   anybody who reads Clients or Reports. Finished is confirmed or published,
   or a report being revised whose earlier version the client still reads. */
create or replace function public.sm_client_reports(p_client uuid)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
begin
  if not public.allowed('clients', 'view') and not public.allowed('reports', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('reports', coalesce((
    select jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'period_start', r.period_start,
             'period_end', r.period_end, 'status', r.status, 'version_no', r.version_no,
             'confirmed_at', r.confirmed_at, 'live_version', v.version_no, 'published_at', v.published_at)
           order by r.period_start desc, r.kind)
      from public.sm_reports r
      left join lateral (select x.version_no, x.published_at from public.sm_report_versions x
                          where x.report_id = r.id and x.withdrawn_at is null
                          order by x.version_no desc limit 1) v on true
     where r.client_id = p_client
       and (r.status in ('confirmed', 'published') or v.version_no is not null)), '[]'::jsonb));
end $$;
grant execute on function public.sm_client_reports(uuid) to authenticated;

/* The file of a finished report: the version the client reads where one is
   published, else the confirmed report as it stands. */
create or replace function public.sm_report_file(p_id uuid)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  r public.sm_reports;
  snap jsonb;
begin
  if not public.allowed('clients', 'view') and not public.allowed('reports', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into r from public.sm_reports where id = p_id;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select x.snapshot into snap from public.sm_report_versions x
   where x.report_id = p_id and x.withdrawn_at is null order by x.version_no desc limit 1;
  if snap is not null then return jsonb_build_object('snapshot', snap); end if;
  if r.status <> 'confirmed' then return jsonb_build_object('error', 'not-finished'); end if;
  return jsonb_build_object('snapshot', public.sm_report_snapshot(p_id, false));
end $$;
grant execute on function public.sm_report_file(uuid) to authenticated;
-- END OF THE REPORTS SECTION
