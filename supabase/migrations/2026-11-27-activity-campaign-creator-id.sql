-- ===========================================================================
-- A CAMPAIGN'S AND A CREATOR'S HISTORY KEPT BY ITS ID (2026-11-27)
-- ===========================================================================
-- WHY: a campaign's Activity read `activity_log` by subject, the title the
-- line was written with, and a creator's by the name; a rename left the
-- earlier lines behind, as a client's did before `activity_log.client_id`
-- (A CLIENT'S HISTORY KEPT BY ITS ID). A record is traced by its id, never
-- by its name.
-- WHAT IT CHANGES
--   * `activity_log.campaign_id` and `activity_log.creator_id` (uuid,
--     nullable, on delete set null), each indexed.
--   * `activity_campaign_note()` / `activity_creator_note()`: after a write
--     to a campaign's own rows (`campaigns`, `campaign_options`,
--     `campaign_confirmations`) or a creator's (`creators` and the tables
--     keyed on one creator), the transaction remembers that id
--     (`adspace.log_campaign`, `adspace.log_creator`) and gives it to the
--     `campaign.*` or `creator.*` lines it already filed without one.
--   * `activity_log_ids()` (before insert): a `campaign.*` line filed
--     without a campaign id takes the one the transaction remembers, a
--     `creator.*` line the creator's. A line given one (the console names
--     the record it acts on) keeps it; an id no longer held is dropped, so
--     the line is still filed. Never resolved from a name.
--   * Backfill: a `campaign.*` line takes the campaign whose title it was
--     written with (its title, and each title a client confirmed it under),
--     a `creator.*` line the creator whose name it was written with (its
--     name and its earlier names from its own `Name: A → B` lines); a name
--     more than one record has held, a line older than the record, and a
--     title a deleted campaign held while this one stood, are left unfilled.
-- ORDER: this file first (the columns must stand before the pages send
-- them), then the pages. An open tab served before reads by name as it did.
-- ROLLBACK: drop trigger activity_log_ids on public.activity_log; drop each
-- `<table>_activity_campaign` and `<table>_activity_creator` trigger; drop
-- function public.activity_log_ids(), public.activity_campaign_note(),
-- public.activity_creator_note(); the pages read by id, so the columns stay
-- (dropping them breaks the console). Safe to run twice.

-- ACTIVITY CAMPAIGN AND CREATOR ID ---------------------------------------------

alter table public.activity_log add column if not exists campaign_id uuid
  references public.campaigns(id) on delete set null;
alter table public.activity_log add column if not exists creator_id uuid
  references public.creators(id) on delete set null;
create index if not exists activity_log_campaign_idx on public.activity_log (campaign_id, created_at desc)
  where campaign_id is not null;
create index if not exists activity_log_creator_idx on public.activity_log (creator_id, created_at desc)
  where creator_id is not null;

create or replace function public.activity_campaign_note()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  j jsonb := to_jsonb(case when tg_op = 'DELETE' then old else new end);
  v uuid;
begin
  v := case when tg_table_name = 'campaigns' then (j ->> 'id')::uuid else (j ->> 'campaign_id')::uuid end;
  if v is null or not exists (select 1 from public.campaigns c where c.id = v) then return null; end if;
  if coalesce(current_setting('adspace.log_campaign', true), '') <> v::text then
    perform set_config('adspace.log_campaign', v::text, true);
    update public.activity_log a set campaign_id = v
     where a.campaign_id is null and a.created_at = now() and a.action like 'campaign.%';
  end if;
  return null;
end $$;
revoke all on function public.activity_campaign_note() from public, anon, authenticated;

create or replace function public.activity_creator_note()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  j jsonb := to_jsonb(case when tg_op = 'DELETE' then old else new end);
  v uuid;
begin
  v := case when tg_table_name = 'creators' then (j ->> 'id')::uuid else (j ->> 'creator_id')::uuid end;
  if v is null or not exists (select 1 from public.creators c where c.id = v) then return null; end if;
  if coalesce(current_setting('adspace.log_creator', true), '') <> v::text then
    perform set_config('adspace.log_creator', v::text, true);
    update public.activity_log a set creator_id = v
     where a.creator_id is null and a.created_at = now() and a.action like 'creator.%';
  end if;
  return null;
end $$;
revoke all on function public.activity_creator_note() from public, anon, authenticated;

create or replace function public.activity_log_ids()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v text;
begin
  if new.campaign_id is not null and not exists (select 1 from public.campaigns c where c.id = new.campaign_id) then
    new.campaign_id := null;
  end if;
  if new.creator_id is not null and not exists (select 1 from public.creators c where c.id = new.creator_id) then
    new.creator_id := null;
  end if;
  if new.campaign_id is null and new.action like 'campaign.%' then
    v := nullif(current_setting('adspace.log_campaign', true), '');
    if v is not null and exists (select 1 from public.campaigns c where c.id = v::uuid) then new.campaign_id := v::uuid; end if;
  end if;
  if new.creator_id is null and new.action like 'creator.%' then
    v := nullif(current_setting('adspace.log_creator', true), '');
    if v is not null and exists (select 1 from public.creators c where c.id = v::uuid) then new.creator_id := v::uuid; end if;
  end if;
  return new;
end $$;
revoke all on function public.activity_log_ids() from public, anon, authenticated;

drop trigger if exists activity_log_ids on public.activity_log;
create trigger activity_log_ids before insert on public.activity_log
  for each row execute function public.activity_log_ids();

do $$
declare t text;
begin
  foreach t in array array['campaigns', 'campaign_options', 'campaign_confirmations'] loop
    if to_regclass('public.' || t) is not null then
      execute format('drop trigger if exists %I on public.%I', t || '_activity_campaign', t);
      execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.activity_campaign_note()',
                     t || '_activity_campaign', t);
    end if;
  end loop;
  foreach t in array array['creators', 'creator_profiles', 'creator_profile_changes', 'creator_emails',
                           'creator_standard_fees', 'creator_earlier_jobs', 'creator_bills', 'creator_pay_requests'] loop
    if to_regclass('public.' || t) is not null then
      execute format('drop trigger if exists %I on public.%I', t || '_activity_creator', t);
      execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.activity_creator_note()',
                     t || '_activity_creator', t);
    end if;
  end loop;
end $$;

-- Backfill: the titles each campaign has held, and the names each creator has.
with held(campaign_id, name) as (
  select c.id, lower(btrim(c.title)) from public.campaigns c where nullif(btrim(c.title), '') is not null
  union
  select f.campaign_id, lower(btrim(f.campaign_title)) from public.campaign_confirmations f
   where f.campaign_id is not null and nullif(btrim(f.campaign_title), '') is not null
),
one as (
  select h.name, min(h.campaign_id::text)::uuid campaign_id from held h group by h.name
  having count(distinct h.campaign_id) = 1
)
update public.activity_log a set campaign_id = o.campaign_id
  from one o, public.campaigns c
 where c.id = o.campaign_id and a.campaign_id is null and a.action like 'campaign.%'
   and lower(btrim(a.subject)) = o.name and a.created_at >= c.created_at
   and not exists (select 1 from public.activity_log d where d.action = 'campaign.deleted'
                    and lower(btrim(d.subject)) = o.name and d.created_at >= c.created_at);

with recursive held(creator_id, name) as (
  select c.id, lower(btrim(c.name)) from public.creators c where nullif(btrim(c.name), '') is not null
  union
  select h.creator_id, lower(btrim(m[1]))
    from held h
    join public.activity_log a on a.action = 'creator.updated' and lower(btrim(a.subject)) = h.name
    cross join lateral regexp_matches(a.detail, 'Name: ([^;→]+) → ([^;]+)', 'g') m
   where lower(btrim(m[2])) = h.name and nullif(btrim(m[1]), '') is not null and lower(btrim(m[1])) <> 'not set'
),
one as (
  select h.name, min(h.creator_id::text)::uuid creator_id from held h group by h.name
  having count(distinct h.creator_id) = 1
)
update public.activity_log a set creator_id = o.creator_id
  from one o, public.creators c
 where c.id = o.creator_id and a.creator_id is null and a.action like 'creator.%'
   and lower(btrim(a.subject)) = o.name and a.created_at >= c.created_at
   and not exists (select 1 from public.activity_log d where d.action = 'creator.removed'
                    and lower(btrim(d.subject)) = o.name and d.created_at >= c.created_at);

-- END OF ACTIVITY CAMPAIGN AND CREATOR ID -------------------------------------

select public.functions_tidy();
