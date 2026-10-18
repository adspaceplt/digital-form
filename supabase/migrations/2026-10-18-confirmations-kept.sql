-- ===========================================================================
-- CONFIRMATIONS KEPT — a client's acceptance of its creators is written once,
-- by its function, and outlives the campaign it confirmed; a campaign's
-- delete is filed by the database. 2026-10-18. Safe to run twice. Rollback
-- at the foot. Mirrored byte for byte in supabase/schema.sql under the same
-- banner; tests/confirmonce.js compares the two.
--
-- WHAT CHANGED (second audit, item 13)
--   1. `campaign_confirmations` is the record of who accepted which creators
--      at which rates. Its insert, update and delete policies let any
--      colleague at Creator Campaigns Work rewrite it and one at Manage
--      remove it. They now admit nothing: every row is written by
--      confirm_selection_with, confirm_selection or campaign_confirm_creators
--      (security definer), and none is changed or removed afterwards.
--   2. Each row keeps the campaign's title and client (`campaign_title`,
--      `client_id`, stamped on insert by campaign_confirmations_stamp and
--      filled in once for the rows before), and the campaign's foreign key,
--      which deleted the rows with the campaign, is taken off: a deleted
--      campaign leaves its confirmations, still naming it.
--   3. A campaign's delete is filed by trigger campaigns_deleted_log in the
--      transaction that deletes (`campaign.deleted`, the title, the invoice
--      number), as delete_client files its own; the page files nothing.
--
-- ROLLBACK
--   alter policy campaign_confirmations_write on public.campaign_confirmations
--     with check (public.allowed('campaigns.campaigns', 'work'));
--   alter policy campaign_confirmations_edit on public.campaign_confirmations
--     using (public.allowed('campaigns.campaigns', 'work')) with check (public.allowed('campaigns.campaigns', 'work'));
--   alter policy campaign_confirmations_del on public.campaign_confirmations
--     using (public.allowed('campaigns.campaigns', 'manage'));
--   drop trigger if exists campaigns_deleted_log on public.campaigns;
--   drop trigger if exists campaign_confirmations_stamp on public.campaign_confirmations;
--   (deploy the earlier pages first, which file the delete themselves; the
--   foreign key is put back only once no row names a deleted campaign:
--   alter table public.campaign_confirmations add constraint
--     campaign_confirmations_campaign_id_fkey foreign key (campaign_id)
--     references public.campaigns(id) on delete cascade;)
-- ===========================================================================

alter table public.campaign_confirmations add column if not exists campaign_title text;
alter table public.campaign_confirmations add column if not exists client_id uuid;

update public.campaign_confirmations k
   set campaign_title = c.title, client_id = c.client_id
  from public.campaigns c
 where c.id = k.campaign_id and k.campaign_title is null;

create or replace function public.campaign_confirmations_stamp()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  select c.title, c.client_id into new.campaign_title, new.client_id
    from public.campaigns c where c.id = new.campaign_id;
  return new;
end $$;
revoke all on function public.campaign_confirmations_stamp() from public, anon, authenticated;
create or replace trigger campaign_confirmations_stamp
  before insert on public.campaign_confirmations
  for each row execute function public.campaign_confirmations_stamp();

alter table public.campaign_confirmations
  drop constraint if exists campaign_confirmations_campaign_id_fkey;

alter policy campaign_confirmations_write on public.campaign_confirmations with check (false);
alter policy campaign_confirmations_edit on public.campaign_confirmations using (false) with check (false);
alter policy campaign_confirmations_del on public.campaign_confirmations using (false);

create or replace function public.campaigns_deleted_log()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  who text := auth.jwt() ->> 'email';
  me  public.team_members;
begin
  if who is not null then
    select * into me from public.team_members where lower(email) = lower(who) and active limit 1;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(me.name, who, 'system'), 'campaign.deleted', old.title, coalesce(old.invoice_no, ''));
  return old;
end $$;
revoke all on function public.campaigns_deleted_log() from public, anon, authenticated;
create or replace trigger campaigns_deleted_log
  after delete on public.campaigns
  for each row execute function public.campaigns_deleted_log();

-- END OF CONFIRMATIONS KEPT -------------------------------------------------

select public.functions_tidy();
