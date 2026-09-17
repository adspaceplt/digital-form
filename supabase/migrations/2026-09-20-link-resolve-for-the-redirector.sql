-- ===========================================================================
-- 2026-09-20  link_resolve(): the one read the hi.adspace.me redirector makes
--
-- WHAT THIS IS FOR
-- hi.adspace.me is now a Cloudflare Worker (workers/links/ in the repository)
-- and it needs to turn a slug into a destination. The plan recorded in
-- supabase/schema.sql was for it to read public.links with the service role,
-- which would have meant putting a key that can read and write every table in
-- this database into a Cloudflare secret so that a redirector could look up
-- one column. This function is the narrower thing that does the same job:
-- one exact slug in, one destination and one state out. No listing, no
-- search, no prefix match, no second column. The public anon key is enough to
-- call it, so nothing that can write ever leaves Supabase.
--
-- What it gives away is what a short link gives away by definition: hold the
-- slug, learn where it goes. That is the redirect itself.
--
-- SAFE TO RUN TWICE. It creates one function and grants execute on it; there
-- is no data migration, no policy change and no table touched. Running it a
-- second time replaces the function with itself.
--
-- ROLLBACK (the redirector stops resolving; nothing else is affected):
--   drop function if exists public.link_resolve(text, text);
-- ===========================================================================

create or replace function public.link_resolve(p_slug text, p_qr text default null)
returns table (url text, state text)
language plpgsql security definer stable set search_path = public as $$
declare
  v_slug   text := lower(btrim(coalesce(p_slug, '')));
  v_code   text := lower(btrim(coalesce(p_qr, '')));
  v_target text;
  v_live   boolean;
begin
  if v_slug = '' then
    return query select null::text, 'missing'::text;
    return;
  end if;

  select l.target_url, l.active into v_target, v_live
    from public.links l
   where l.slug = v_slug;

  if v_target is null then
    return query select null::text, 'missing'::text;
    return;
  end if;
  if not v_live then
    return query select null::text, 'paused'::text;
    return;
  end if;

  -- A scan carries its code; a typed link does not, and is never turned away
  -- by one. A code belonging to another slug is as revoked as a dead one.
  if v_code <> '' and not exists (
       select 1 from public.link_qrs q
        where q.code = v_code and q.slug = v_slug and q.active) then
    return query select null::text, 'revoked'::text;
    return;
  end if;

  return query select v_target, 'ok'::text;
end $$;

revoke all on function public.link_resolve(text, text) from public;
grant execute on function public.link_resolve(text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Verification. Rolls itself back, so it leaves no rows behind.
-- ---------------------------------------------------------------------------
do $$
declare r record;
begin
  insert into public.links (slug, target_url, active)
       values ('zz-migration-check', 'https://adspacestudios.com/x', true);
  insert into public.link_qrs (code, slug, active)
       values ('zzcheck1', 'zz-migration-check', true),
              ('zzcheck2', 'zz-migration-check', false);

  select * into r from public.link_resolve('zz-migration-check');
  if r.state <> 'ok' or r.url <> 'https://adspacestudios.com/x' then
    raise exception 'link_resolve: a live slug did not resolve (% / %)', r.state, r.url;
  end if;

  -- The slug is matched as typed in any case, the way a printed link is read.
  select * into r from public.link_resolve('  ZZ-Migration-Check  ');
  if r.state <> 'ok' then raise exception 'link_resolve: case and space not normalised'; end if;

  select * into r from public.link_resolve('zz-migration-check', 'zzcheck1');
  if r.state <> 'ok' then raise exception 'link_resolve: a live code was turned away'; end if;

  select * into r from public.link_resolve('zz-migration-check', 'zzcheck2');
  if r.state <> 'revoked' then raise exception 'link_resolve: a revoked code resolved'; end if;

  select * into r from public.link_resolve('zz-nothing-here');
  if r.state <> 'missing' then raise exception 'link_resolve: an unknown slug did not read missing'; end if;

  update public.links set active = false where slug = 'zz-migration-check';
  select * into r from public.link_resolve('zz-migration-check');
  if r.state <> 'paused' then raise exception 'link_resolve: a paused link did not read paused'; end if;

  raise notice 'link_resolve: ok';
  -- Nothing above is meant to survive.
  delete from public.links where slug = 'zz-migration-check';
end $$;
