-- ===========================================================================
-- THE CAMPAIGN CLOCK — when a campaign moved, and when each booking finished.
-- 2026-09-26. Safe to run twice. Rollback at the foot. Mirrored in
-- supabase/schema.sql under the same banner.
--
-- Asked for by the user: an internal timing under Key dates, from created
-- through confirmed and in production to completed, each stage's hours. The
-- page reads it; nothing client-facing sends it.
--
--   1. `campaigns.state_log`: every state the campaign has been in, with when,
--      stamped by a trigger on the move, never by a page. A new campaign
--      starts with its first state at its creation time. Campaigns that
--      existed before this have no log of their past moves: the page omits
--      a stage it cannot date rather than guessing.
--
--   2. `campaign_options.completed_at`: stamped when a booking reaches
--      Completed and cleared if it is reverted, so a campaign is complete at
--      the moment its last booking was.
--
-- ROLLBACK
--   drop trigger if exists campaigns_state_clock on public.campaigns;
--   drop function if exists public.campaigns_state_clock();
--   drop trigger if exists campaign_options_done_clock on public.campaign_options;
--   drop function if exists public.campaign_options_done_clock();
--   alter table public.campaigns drop column if exists state_log;
--   alter table public.campaign_options drop column if exists completed_at;
-- ===========================================================================

alter table public.campaigns add column if not exists state_log jsonb not null default '[]'::jsonb;

create or replace function public.campaigns_state_clock()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    if new.state_log is null or jsonb_array_length(new.state_log) = 0 then
      new.state_log := jsonb_build_array(
        jsonb_build_object('state', new.state, 'at', coalesce(new.created_at, now())));
    end if;
    return new;
  end if;
  if new.state is distinct from old.state then
    new.state_log := coalesce(old.state_log, '[]'::jsonb) ||
      jsonb_build_array(jsonb_build_object('state', new.state, 'at', now()));
  end if;
  return new;
end $$;

drop trigger if exists campaigns_state_clock on public.campaigns;
create trigger campaigns_state_clock before insert or update on public.campaigns
  for each row execute function public.campaigns_state_clock();

alter table public.campaign_options add column if not exists completed_at timestamptz;

create or replace function public.campaign_options_done_clock()
returns trigger
language plpgsql
as $$
begin
  if new.state = 'completed' then
    if tg_op = 'INSERT' or old.state is distinct from 'completed' then
      new.completed_at := now();
    end if;
  else
    new.completed_at := null;
  end if;
  return new;
end $$;

drop trigger if exists campaign_options_done_clock on public.campaign_options;
create trigger campaign_options_done_clock before insert or update on public.campaign_options
  for each row execute function public.campaign_options_done_clock();
-- END OF THE CAMPAIGN CLOCK -------------------------------------------------
