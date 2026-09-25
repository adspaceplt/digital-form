-- 2026-09-25 · Social media reports
--
-- Run once in the Supabase SQL editor, after every earlier migration. Safe to
-- run twice: every statement is `create ... if not exists`, `create or
-- replace`, or a policy or trigger dropped before it is made. Mirrored in
-- supabase/schema.sql (the section under the banner below, and
-- activity_section), compared byte for byte by tests/sql.js.

-- =========================================================================
-- SOCIAL MEDIA REPORTS
--
-- A client's monthly social media report: the accounts, every post with its
-- figures, and the team's findings, kept as rows and drawn as a PDF in the
-- browser by js/smreport.js. Asked for by the user on 2026-09-25: the client
-- reads the final report in their own portal, and only once the team has
-- finished it, confirmed it and published it.
--
--   draft  -> review     Submit for review          clients.reports Work
--   review -> draft      Return (a note)            the submitter, or Manage
--   review -> confirmed  Confirm                    Manage, never the submitter
--   confirmed -> draft   Return (a note)            Manage
--   confirmed -> published  Publish                 Manage
--   published -> draft   Revise (the next version)  Work
--   published -> confirmed  Unpublish (a reason)    Manage
--
-- Nothing a client reads is ever a row somebody is still editing. Publishing
-- freezes the report into `sm_report_versions.snapshot`, and the client
-- portal reads only that, the newest version not withdrawn. A revision is a
-- new draft with the next version number; the client goes on reading the
-- version they have until the revision is published.
--
-- The rows are edited directly by the console under row level security
-- (`clients.reports` Work), but only while the report is a draft: a trigger
-- refuses any change to the report's content, its accounts or its posts once
-- it has been submitted, and refuses any change to its status, version or
-- stamps except from the functions below. A browser cannot publish a report
-- by writing a column.
--
-- Thumbnails are kept in the row as small JPEG data URLs (the editor scales
-- them to 320px), not on the CDN: the PDF is drawn in the browser, and the
-- CDN does not answer a cross-origin read, so a CDN thumbnail could not be
-- drawn into the file.
--
-- Rollback:
--   drop function if exists public.portal_report(uuid);
--   drop function if exists public.portal_reports(uuid);
--   drop function if exists public.sm_report_delete(uuid, text);
--   drop function if exists public.sm_report_unpublish(uuid, text);
--   drop function if exists public.sm_report_revise(uuid);
--   drop function if exists public.sm_report_publish(uuid);
--   drop function if exists public.sm_report_confirm(uuid);
--   drop function if exists public.sm_report_return(uuid, text);
--   drop function if exists public.sm_report_submit(uuid);
--   drop function if exists public.sm_report_create(uuid, date, date, text);
--   drop function if exists public.sm_report_snapshot(uuid, boolean);
--   drop function if exists public.sm_report_log(uuid, text, text);
--   drop table if exists public.sm_report_versions, public.sm_report_posts,
--     public.sm_report_platforms, public.sm_reports;
--   drop function if exists public.sm_report_guard(), public.sm_report_child_guard();
--   and re-run the activity_section of 2026-09-24-creator-profile.sql.
-- =========================================================================

create table if not exists public.sm_reports (
  id            uuid primary key default gen_random_uuid(),
  client_id     uuid not null references public.clients(id) on delete cascade,
  -- Which report this is. One engine of steps for every kind; the kind
  -- decides what is entered and how the PDF is drawn. Social media is built,
  -- advertising is next.
  kind          text not null default 'social',
  title         text not null default 'Social Media Report',
  period_start  date not null,
  period_end    date not null,
  headline      text,
  intro         text,
  insights      jsonb not null default '{}'::jsonb,
  rank_metric   text not null default 'views',
  status        text not null default 'draft',
  version_no    integer not null default 1,
  return_note   text,
  submitted_by  uuid references public.team_members(id) on delete set null,
  submitted_at  timestamptz,
  confirmed_by  uuid references public.team_members(id) on delete set null,
  confirmed_at  timestamptz,
  created_by    uuid references public.team_members(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint sm_reports_status check (status in ('draft', 'review', 'confirmed', 'published')),
  constraint sm_reports_kind check (kind in ('social', 'ads')),
  constraint sm_reports_rank check (rank_metric in ('views', 'reach', 'impressions', 'engagements', 'interactions')),
  constraint sm_reports_period check (period_end >= period_start),
  constraint sm_reports_title check (length(btrim(title)) between 1 and 120)
);
create unique index if not exists sm_reports_client_period_idx
  on public.sm_reports (client_id, kind, period_start, period_end);

create table if not exists public.sm_report_platforms (
  id              uuid primary key default gen_random_uuid(),
  report_id       uuid not null references public.sm_reports(id) on delete cascade,
  platform        text not null,
  account_name    text,
  handle          text,
  group_key       text,
  group_label     text,
  position        integer not null default 0,
  metrics         text[] not null default array['views', 'engagements'],
  followers_start bigint,
  followers_end   bigint,
  growth_override bigint,
  growth_reason   text,
  er_basis        text,
  metric_notes    text,
  summary         text,
  worked          text,
  improve         text,
  actions         text,
  created_at      timestamptz not null default now(),
  constraint sm_platforms_platform check (platform in ('facebook', 'instagram', 'tiktok', 'rednote', 'youtube', 'linkedin', 'x', 'threads', 'other')),
  constraint sm_platforms_basis check (er_basis is null or er_basis in ('views', 'reach', 'impressions', 'followers'))
);
create index if not exists sm_report_platforms_report_idx on public.sm_report_platforms (report_id);

create table if not exists public.sm_report_posts (
  id            uuid primary key default gen_random_uuid(),
  report_id     uuid not null references public.sm_reports(id) on delete cascade,
  platform_id   uuid not null references public.sm_report_platforms(id) on delete cascade,
  posted_on     date,
  title         text,
  caption       text,
  content_type  text,
  url           text,
  thumb_data    text,
  views         bigint,
  reach         bigint,
  impressions   bigint,
  interactions  bigint,
  engagements   bigint,
  likes         bigint,
  comments      bigint,
  shares        bigint,
  saves         bigint,
  notable       text,
  observation   text,
  position      integer not null default 0,
  created_at    timestamptz not null default now(),
  constraint sm_posts_thumb check (thumb_data is null or (thumb_data like 'data:image/%' and length(thumb_data) <= 300000))
);
create index if not exists sm_report_posts_report_idx on public.sm_report_posts (report_id);

create table if not exists public.sm_report_versions (
  id               uuid primary key default gen_random_uuid(),
  report_id        uuid not null references public.sm_reports(id) on delete cascade,
  version_no       integer not null,
  snapshot         jsonb not null,
  published_by     text,
  published_at     timestamptz not null default now(),
  withdrawn_at     timestamptz,
  withdrawn_by     text,
  withdraw_reason  text,
  unique (report_id, version_no)
);

alter table public.sm_reports enable row level security;
alter table public.sm_report_platforms enable row level security;
alter table public.sm_report_posts enable row level security;
alter table public.sm_report_versions enable row level security;

drop policy if exists sm_reports_read on public.sm_reports;
create policy sm_reports_read on public.sm_reports for select to authenticated
  using (public.allowed('clients.reports', 'view'));
drop policy if exists sm_reports_write on public.sm_reports;
create policy sm_reports_write on public.sm_reports for update to authenticated
  using (public.allowed('clients.reports', 'work')) with check (public.allowed('clients.reports', 'work'));
drop policy if exists sm_platforms_all on public.sm_report_platforms;
create policy sm_platforms_all on public.sm_report_platforms for all to authenticated
  using (public.allowed('clients.reports', 'view')) with check (public.allowed('clients.reports', 'work'));
drop policy if exists sm_posts_all on public.sm_report_posts;
create policy sm_posts_all on public.sm_report_posts for all to authenticated
  using (public.allowed('clients.reports', 'view')) with check (public.allowed('clients.reports', 'work'));
drop policy if exists sm_versions_read on public.sm_report_versions;
create policy sm_versions_read on public.sm_report_versions for select to authenticated
  using (public.allowed('clients.reports', 'view'));
-- A report's rows are removed only by the functions; a platform or a post
-- may be deleted directly while its report is a draft, which the guard below
-- decides. The versions are written by the functions alone.

/* The functions below set this for their own transaction. Nothing a browser
   sends can: `set_config` is not reachable through PostgREST, and the
   setting lives only as long as the function's own transaction. */
create or replace function public.sm_report_guard()
returns trigger
language plpgsql set search_path = public as $$
begin
  if coalesce(current_setting('adspace.sm_fn', true), '') = 'on' then
    new.updated_at := now();
    return new;
  end if;
  if new.status is distinct from old.status or new.version_no is distinct from old.version_no
     or new.submitted_by is distinct from old.submitted_by or new.submitted_at is distinct from old.submitted_at
     or new.confirmed_by is distinct from old.confirmed_by or new.confirmed_at is distinct from old.confirmed_at
     or new.return_note is distinct from old.return_note or new.client_id is distinct from old.client_id
     or new.kind is distinct from old.kind
     or new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at then
    raise exception 'sm-status-by-function' using errcode = 'P0001';
  end if;
  if old.status <> 'draft' then
    raise exception 'sm-not-draft' using errcode = 'P0001';
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists sm_reports_guard on public.sm_reports;
create trigger sm_reports_guard before update on public.sm_reports
  for each row execute function public.sm_report_guard();

create or replace function public.sm_report_child_guard()
returns trigger
language plpgsql set search_path = public as $$
declare
  st text;
  rid uuid := case when tg_op = 'DELETE' then old.report_id else new.report_id end;
begin
  if coalesce(current_setting('adspace.sm_fn', true), '') = 'on' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if tg_op = 'UPDATE' and new.report_id is distinct from old.report_id then
    raise exception 'sm-not-draft' using errcode = 'P0001';
  end if;
  select status into st from public.sm_reports where id = rid;
  -- The report itself is going (a client deleted, a cascade): nothing to guard.
  if st is null and tg_op = 'DELETE' then return old; end if;
  if st is distinct from 'draft' then
    raise exception 'sm-not-draft' using errcode = 'P0001';
  end if;
  -- A post is filed only under an account of its own report. Read through
  -- jsonb, because PL/pgSQL resolves `new.platform_id` on the accounts
  -- table too, where there is no such column.
  if tg_table_name = 'sm_report_posts' and tg_op <> 'DELETE' then
    if not exists (select 1 from public.sm_report_platforms p
                    where p.id = (to_jsonb(new) ->> 'platform_id')::uuid and p.report_id = new.report_id) then
      raise exception 'sm-wrong-platform' using errcode = 'P0001';
    end if;
  end if;
  update public.sm_reports set updated_at = now() where id = rid and status = 'draft'
    and updated_at < now() - interval '1 second';
  return case when tg_op = 'DELETE' then old else new end;
end $$;
drop trigger if exists sm_platforms_guard on public.sm_report_platforms;
create trigger sm_platforms_guard before insert or update or delete on public.sm_report_platforms
  for each row execute function public.sm_report_child_guard();
drop trigger if exists sm_posts_guard on public.sm_report_posts;
create trigger sm_posts_guard before insert or update or delete on public.sm_report_posts
  for each row execute function public.sm_report_child_guard();

/* The period in words, as the report and the activity record name it. */
create or replace function public.sm_period_word(p_start date, p_end date)
returns text
language sql immutable set search_path = public as $$
  select case
    when p_start = date_trunc('month', p_start)::date
     and p_end = (date_trunc('month', p_start) + interval '1 month - 1 day')::date
      then trim(to_char(p_start, 'FMMonth YYYY'))
    else to_char(p_start, 'FMDD Mon YYYY') || ' to ' || to_char(p_end, 'FMDD Mon YYYY')
  end
$$;

create or replace function public.sm_report_log(p_id uuid, p_action text, p_extra text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  r public.sm_reports;
  who text;
  cname text;
begin
  select * into r from public.sm_reports where id = p_id;
  select c.name into cname from public.clients c where c.id = r.client_id;
  who := coalesce((public.ops_me()).name, auth.jwt() ->> 'email');
  insert into public.activity_log (actor, action, subject, detail)
  values (who, p_action, cname,
          public.sm_period_word(r.period_start, r.period_end) || ' · v' || r.version_no
          || coalesce(' · ' || nullif(btrim(p_extra), ''), ''));
end $$;
revoke all on function public.sm_report_log(uuid, text, text) from public, anon, authenticated;

/* The whole report as js/smreport.js reads it. `p_final` is the published
   form: the status the PDF prints as issued, and the time it was issued. */
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
      'period_start', r.period_start, 'period_end', r.period_end,
      'headline', r.headline, 'intro', r.intro, 'insights', r.insights, 'rank_metric', r.rank_metric,
      'status', case when p_final then 'final' else r.status end,
      'version_no', r.version_no, 'generated_at', now(),
      'prepared_by_name', (select name from public.team_members where id = r.submitted_by)),
    'platforms', coalesce((select jsonb_agg(to_jsonb(p) - 'created_at' order by p.position, p.created_at)
                  from public.sm_report_platforms p where p.report_id = r.id), '[]'::jsonb),
    'posts', coalesce((select jsonb_agg((to_jsonb(q) - 'created_at' - 'thumb_data') || jsonb_build_object('thumb_url', q.thumb_data)
                  order by q.posted_on nulls last, q.position, q.created_at)
                  from public.sm_report_posts q where q.report_id = r.id), '[]'::jsonb));
end $$;
grant execute on function public.sm_report_snapshot(uuid, boolean) to authenticated;

/* A new report of a kind for a client and a period. The accounts of the
   client's latest earlier report of the same kind are carried forward, each
   starting with the followers that report ended on, so a month starts with
   its accounts in place and only the figures to type. Only the kinds the
   console can draw are accepted. */
create or replace function public.sm_report_create(p_client uuid, p_start date, p_end date, p_kind text default 'social')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  rid uuid;
  prev uuid;
begin
  if me.id is null or not public.allowed('clients.reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_client is null or not exists (select 1 from public.clients where id = p_client) then
    return jsonb_build_object('error', 'not-found');
  end if;
  if p_start is null or p_end is null or p_end < p_start then return jsonb_build_object('error', 'bad-period'); end if;
  if coalesce(p_kind, '') not in ('social') then return jsonb_build_object('error', 'bad-kind'); end if;
  select id into rid from public.sm_reports
   where client_id = p_client and kind = p_kind and period_start = p_start and period_end = p_end;
  if rid is not null then return jsonb_build_object('error', 'exists', 'id', rid); end if;
  perform set_config('adspace.sm_fn', 'on', true);
  insert into public.sm_reports (client_id, kind, period_start, period_end, created_by)
  values (p_client, p_kind, p_start, p_end, me.id) returning id into rid;
  select id into prev from public.sm_reports
   where client_id = p_client and kind = p_kind and id <> rid and period_start < p_start
   order by period_start desc limit 1;
  if prev is not null then
    insert into public.sm_report_platforms (report_id, platform, account_name, handle, group_key, group_label,
      position, metrics, followers_start, er_basis, metric_notes)
    select rid, p.platform, p.account_name, p.handle, p.group_key, p.group_label, p.position, p.metrics,
           coalesce(p.followers_end, case when p.followers_start is not null and p.growth_override is not null
                                          then p.followers_start + p.growth_override end),
           p.er_basis, p.metric_notes
      from public.sm_report_platforms p where p.report_id = prev;
  end if;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(rid, 'report.created');
  return jsonb_build_object('ok', true, 'id', rid, 'carried', prev is not null);
end $$;
grant execute on function public.sm_report_create(uuid, date, date, text) to authenticated;

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
  if not exists (select 1 from public.sm_report_platforms where report_id = p_id) then
    return jsonb_build_object('error', 'no-platforms');
  end if;
  if not exists (select 1 from public.sm_report_posts where report_id = p_id) then
    return jsonb_build_object('error', 'no-posts');
  end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set status = 'review', submitted_by = me.id, submitted_at = now(),
    return_note = null, confirmed_by = null, confirmed_at = null where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.submitted');
  return jsonb_build_object('ok', true, 'status', 'review');
end $$;
grant execute on function public.sm_report_submit(uuid) to authenticated;

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
  if me.id is null or not public.allowed('clients.reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status not in ('review', 'confirmed') then return jsonb_build_object('error', 'not-returnable', 'status', r.status); end if;
  if not public.allowed('clients.reports', 'manage')
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
  if me.id is null or not public.allowed('clients.reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
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
  if me.id is null or not public.allowed('clients.reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
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
  if me.id is null or not public.allowed('clients.reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
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
  if me.id is null or not public.allowed('clients.reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
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
  if me.id is null or not public.allowed('clients.reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
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

/* The client portal: the newest version of each report that stands, for a
   client the signed-in address may open, and one version's snapshot. */
create or replace function public.portal_reports(p_client uuid)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
begin
  if auth.jwt() ->> 'email' is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  if p_client is null or p_client not in (select public.portal_clients()) then
    return jsonb_build_object('error', 'no-access');
  end if;
  return jsonb_build_object('reports', coalesce((
    select jsonb_agg(jsonb_build_object('id', v.id, 'kind', r.kind, 'title', r.title, 'period_start', r.period_start,
             'period_end', r.period_end, 'version_no', v.version_no, 'published_at', v.published_at)
           order by r.period_start desc)
      from public.sm_reports r
      join lateral (select * from public.sm_report_versions x
                     where x.report_id = r.id and x.withdrawn_at is null
                     order by x.version_no desc limit 1) v on true
     where r.client_id = p_client), '[]'::jsonb));
end $$;
revoke all on function public.portal_reports(uuid) from public, anon;
grant execute on function public.portal_reports(uuid) to authenticated;

create or replace function public.portal_report(p_version uuid)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  v public.sm_report_versions;
  cid uuid;
begin
  if auth.jwt() ->> 'email' is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  select * into v from public.sm_report_versions where id = p_version and withdrawn_at is null;
  if v.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select client_id into cid from public.sm_reports where id = v.report_id;
  if cid is null or cid not in (select public.portal_clients()) then return jsonb_build_object('error', 'not-found'); end if;
  if exists (select 1 from public.sm_report_versions x where x.report_id = v.report_id
              and x.withdrawn_at is null and x.version_no > v.version_no) then
    return jsonb_build_object('error', 'not-found');
  end if;
  return jsonb_build_object('snapshot', v.snapshot);
end $$;
revoke all on function public.portal_report(uuid) from public, anon;
grant execute on function public.portal_report(uuid) to authenticated;

revoke all on function public.sm_report_guard() from public, anon, authenticated;
revoke all on function public.sm_report_child_guard() from public, anon, authenticated;
-- END OF SOCIAL MEDIA REPORTS

-- The activity record's section map, with the report's tags filed under
-- Clients, where the Reports pane is. Identical to activity_section in
-- supabase/schema.sql.
create or replace function public.activity_section(p_action text)
returns text
language sql immutable parallel safe as $$
  select case
    when action in ('campaign.bulk', 'campaign.closed', 'campaign.confirmed',
                    'campaign.created', 'campaign.deleted', 'campaign.edited',
                    'campaign.file_added', 'campaign.qc',
                    'campaign.invoice', 'campaign.invoice_file',
                    'campaign.invoice_removed', 'campaign.keyed', 'campaign.locked',
                    'campaign.opened', 'campaign.rate', 'campaign.rated',
                    'campaign.reinstated', 'campaign.replaced', 'campaign.review',
                    'campaign.stage', 'campaign.submitted', 'campaign.unbooked',
                    'campaign.unkeyed', 'campaign.withdrawn', 'creator.added',
                    'creator.code', 'creator.links', 'creator.links_restored',
                    'creator.links_self', 'creator.off', 'creator.on', 'creator.removed',
                    'creator.updated') then 'campaigns'
    when action in ('client.action_done', 'client.action_reopened', 'client.added',
                    'client.billing', 'client.brand', 'client.edited',
                    'client.review_on', 'client.service', 'client.service_changed',
                    'client.service_removed', 'client.stage', 'client.touch',
                    'client.touch_edited', 'client.touch_removed',
                    'client.touch_restored', 'contact.added', 'contact.deleted',
                    'contact.edited', 'contact.portal_invite', 'contact.portal_off',
                    'contact.portal_on', 'contact.primary', 'contact.removed',
                    'contact.restored', 'report.confirmed', 'report.created',
                    'report.deleted', 'report.published', 'report.returned',
                    'report.revised', 'report.submitted', 'report.unpublished',
                    'request.changed', 'request.raised',
                    'request.reinstated', 'request.replied', 'request.withdrawn',
                    'service.override') then 'clients'
    when action in ('qr.created', 'qr.restored', 'qr.revoked', 'shortlink.created',
                    'shortlink.deleted', 'shortlink.imported', 'shortlink.updated') then 'links'
    when action in ('ops.deleted', 'ops.month_deleted', 'ops.numbering') then 'ops'
    when action in ('document.deleted', 'document.issued', 'document.reissued',
                    'document.restored', 'document.signed', 'document.superseded',
                    'document.unsigned', 'document.verified', 'document.voided',
                    'register.added', 'register.edited') then 'register'
    when action in ('client.drive', 'client.handles', 'client.profile',
                    'client.removed', 'drive.imported', 'link.reset', 'post.added',
                    'post.deleted', 'post.edited', 'reapproval.requested',
                    'review.approved', 'review.changes', 'review.removed',
                    'set.created', 'set.deleted', 'set.published', 'set.renamed',
                    'set.withdrawn') then 'review'
    when action in ('service.added', 'service.changed', 'service.deleted',
                    'service.off', 'service.on') then 'services'
    when action in ('team.added', 'team.changed', 'team.edited', 'team.group_added',
                    'team.group_changed', 'team.group_removed', 'team.invited') then 'team'
    else 'other'
  end
  from (select p_action as action) t
$$;
grant execute on function public.activity_section(text) to authenticated;
