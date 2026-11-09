-- ===========================================================================
-- CREATOR AND CAMPAIGN IDS TAKEN AS THE DATABASE (2026-11-09)
-- ===========================================================================
-- WHY (security audit run 2, 2026-11-09; the user's scheduled audit: "fix and
-- release confirmed ones"):
-- Adding a creator or a campaign failed: the ID triggers ran as the colleague and
-- called id_take, which no colleague may run.
--
-- WHAT IT CHANGES
--   creators_creator_code and campaigns_campaign_code run as security definer; a
--   signed-in caller cannot set an ID on a row that has none.
--
-- ORDER: this file, then the pages. Safe to run twice.
--
-- ROLLBACK: run the CREATOR AND CAMPAIGN IDS band's two trigger functions again.
-- ===========================================================================

-- CREATOR AND CAMPAIGN IDS TAKEN AS THE DATABASE ---------------------------

/* Adding a creator or a campaign takes its next ID (security audit
   2026-11-09, a defect found beside it): creators_creator_code and
   campaigns_campaign_code ran as the colleague and called id_take, which no
   colleague may run, so every insert failed with permission denied. They
   run as the database now, and an ID once given never changes; a signed-in
   caller cannot set one on a row that has none (only the SQL Editor or the
   migration's backfill, with no signed-in caller, may). */
create or replace function public.creators_creator_code()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.creator_code := public.id_take('creator');
  elsif new.creator_code is distinct from old.creator_code
        and (old.creator_code is not null or coalesce(auth.jwt() ->> 'email', '') <> '') then
    raise exception 'code-fixed';
  end if;
  return new;
end $$;
revoke all on function public.creators_creator_code() from public, anon, authenticated;

create or replace function public.campaigns_campaign_code()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.campaign_code := public.id_take('campaign');
  elsif new.campaign_code is distinct from old.campaign_code
        and (old.campaign_code is not null or coalesce(auth.jwt() ->> 'email', '') <> '') then
    raise exception 'code-fixed';
  end if;
  return new;
end $$;
revoke all on function public.campaigns_campaign_code() from public, anon, authenticated;

-- END OF CREATOR AND CAMPAIGN IDS TAKEN AS THE DATABASE ---------------------


select public.functions_tidy();
