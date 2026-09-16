-- 2026-09-20 — one set of handles per client, and hard delete behind can_remove.
--
-- Two things, both additive and safe to run twice:
--
--   1. The brand profile and Content Review's client settings were two sets of
--      fields over one client: `social_ig` … `social_xhs` on the record, and
--      `handle_ig` … `handle_xhs` on the review settings, plus a logo only the
--      review settings could set. A handle corrected on the record therefore
--      left the one printed on the client's own mockup untouched. The console
--      now edits the `handle_*` columns in both places, so this backfills the
--      brand values into them where a handle is still empty. Nothing is
--      dropped: `social_*` keeps whatever it held and simply stops being
--      written.
--
--   2. `delete_client` gains `allowed('remove')`. It already refused anyone
--      who is not on the team; within the team, deleting a client is the same
--      authority that hard-deletes a contact, a rate card line or a letter,
--      and the console now offers the action, so the database checks it again
--      when the button is pressed.
--
-- Rollback is at the foot.

-- ---- 1. one set of handles -------------------------------------------------

/* What a brand field was holding. A bare handle is taken as typed. A pasted
   profile URL gives up its last path segment, but only when that segment
   reads like a name: `instagram.com/p/DXyz` and `facebook.com/pages/...`
   would otherwise print a route fragment on a client's post, which is worse
   than printing nothing and being asked to fill it in. */
create or replace function public.handle_of(p_value text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v     text := btrim(coalesce(p_value, ''));
  parts text[];
  last  text;
  ROUTE_WORDS constant text[] := array['p', 'profile', 'profiles', 'pages', 'page',
                    'user', 'users', 'home', 'reel', 'video', 'explore', 'share'];
begin
  if v = '' then return null; end if;
  if v !~* '^https?://' then return v; end if;

  v := rtrim(split_part(split_part(v, '?', 1), '#', 1), '/');
  parts := regexp_split_to_array(v, '/');
  last := parts[array_length(parts, 1)];
  if last is null or btrim(last) = '' then return null; end if;
  last := ltrim(btrim(last), '@');

  /* A route, not a person — either as the last segment, or as the one before
     it, which makes the last an id: `instagram.com/p/DXyz123` is a post and
     printing `DXyz123` on a client's own mockup is worse than printing
     nothing and being asked for the handle. */
  if lower(last) = any (ROUTE_WORDS) then return null; end if;
  if array_length(parts, 1) > 1
     and lower(ltrim(btrim(parts[array_length(parts, 1) - 1]), '@')) = any (ROUTE_WORDS)
  then return null; end if;
  if last !~ '^[A-Za-z0-9._-]{1,40}$' then return null; end if;
  return last;
end $$;

update public.clients set handle_ig = public.handle_of(social_ig)
 where coalesce(btrim(handle_ig), '') = ''
   and public.handle_of(social_ig) is not null;
update public.clients set handle_fb = public.handle_of(social_fb)
 where coalesce(btrim(handle_fb), '') = ''
   and public.handle_of(social_fb) is not null;
update public.clients set handle_tiktok = public.handle_of(social_tiktok)
 where coalesce(btrim(handle_tiktok), '') = ''
   and public.handle_of(social_tiktok) is not null;
update public.clients set handle_xhs = public.handle_of(social_xhs)
 where coalesce(btrim(handle_xhs), '') = ''
   and public.handle_of(social_xhs) is not null;

-- ---- 2. deleting a client is the remove authority --------------------------
create or replace function public.delete_client(p_client uuid, p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  want text;
  who  text := auth.jwt() ->> 'email';
begin
  if who is null then
    raise exception 'Not signed in';
  end if;
  if not public.is_team() then
    raise exception 'Not allowed';
  end if;
  if not public.allowed('remove') then
    raise exception 'Not allowed';
  end if;
  select value into want from public.app_secrets where key = 'delete_code';
  if want is not null and want <> '' then
    if p_code is null or p_code <> want then
      return 'wrong-code';
    end if;
  end if;
  delete from public.clients where id = p_client;
  if not found then
    return 'not-found';
  end if;
  return 'deleted';
end $$;

revoke all on function public.delete_client(uuid, text) from anon;
grant execute on function public.delete_client(uuid, text) to authenticated;

-- ---- 3. verification -------------------------------------------------------
-- Each row should read 1.
select 'handle_of exists' as check_name, count(*) from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'handle_of'
union all
select 'delete_client checks can_remove', count(*) from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'delete_client'
   and p.prosrc like '%allowed(''remove'')%';

-- How many clients now carry a handle on each platform, for the record.
select count(*) filter (where coalesce(btrim(handle_ig), '') <> '')     as instagram,
       count(*) filter (where coalesce(btrim(handle_fb), '') <> '')     as facebook,
       count(*) filter (where coalesce(btrim(handle_tiktok), '') <> '') as tiktok,
       count(*) filter (where coalesce(btrim(handle_xhs), '') <> '')    as rednote
  from public.clients;

/* ---- Rollback -------------------------------------------------------------
   The backfill only filled handles that were empty, so it is undone by
   clearing the ones that match what the brand field still holds:

   update public.clients set handle_ig = null
    where handle_ig = public.handle_of(social_ig);
   -- and the same for handle_fb, handle_tiktok, handle_xhs.

   drop function if exists public.handle_of(text);

   The permission check is removed by re-running the copy of `delete_client`
   in supabase/schema.sql from before this change.
--------------------------------------------------------------------------- */
