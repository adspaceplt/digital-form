-- ===========================================================================
-- SHORT LINKS RE-LETTERED — a campaign's creator selection is /s/, Video
-- Scripts /v/, and /c opens the client portal (2026-10-15)
-- ===========================================================================
-- WHY (the user, 2026-10-15: "Can creator campaign use hi.adspace.me/s
--   instead of /c, reserve hi.adspace.me/c to client portal"; "use v for
--   video script, take s back for selection")
--   Links already sent keep working: an /s/ key that is a client's Video
--   Scripts key still opens their scripts, and /c/{key} still opens its
--   campaign; only a bare /c is the client portal.
--
-- WHAT CHANGED
--   * `share_link_preview(p_kind, p_key)` answers a fourth kind, `which`:
--     whether a key is a campaign's selection key (`campaign`) or a client's
--     Video Scripts key (`script`), else nothing. The links Worker asks it
--     for /s/{key}. The two keys never overlap; a campaign is tried first.
--     The function stays anon's (already in `open_to_anon`).
--
-- ORDER
--   This file, then the Worker (its new code pasted in Cloudflare), then
--   `shareLetters` turned on in js/config.js. Until the Worker is live the
--   console keeps giving /c/ and /s/ as before.
--
-- Safe to run twice. Rollback: run the section SHARE LINK PREVIEW of
-- 2026-10-13-share-link-preview.sql again.
-- ===========================================================================
create or replace function public.share_link_preview(p_kind text, p_key text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(case p_kind
    when 'which' then (
      select case
        when exists (select 1 from public.campaigns k where k.access_token = p_key) then jsonb_build_object('kind', 'campaign')
        when exists (select 1 from public.clients c where c.script_key = p_key) then jsonb_build_object('kind', 'script')
      end
       where p_key ~ '^[A-Za-z0-9_-]{6,64}$')
    when 'script' then (
      select jsonb_strip_nulls(jsonb_build_object('brand', c.name))
        from public.clients c
       where p_key ~ '^[A-Za-z0-9_-]{6,64}$'
         and c.script_key = p_key and c.active
         and exists (select 1 from public.video_scripts s where s.client_id = c.id and s.status = 'shared')
       limit 1)
    when 'campaign' then (
      select jsonb_strip_nulls(jsonb_build_object('brand', c.name, 'title', nullif(btrim(k.title), '')))
        from public.campaigns k
        join public.clients c on c.id = k.client_id
       where p_key ~ '^[A-Za-z0-9_-]{6,64}$'
         and k.access_token = p_key
         and coalesce(k.passcode, '') = '' and k.state <> 'draft'
       limit 1)
    when 'creator' then (
      select case when count(*) = 1 then jsonb_strip_nulls(jsonb_build_object('brand', min(c.name), 'title', nullif(btrim(min(k.title)), ''))) end
        from public.creators cr
        join public.campaign_options o on o.creator_id = cr.id
         and o.state in ('confirmed', 'pending_visit', 'pending_draft', 'submitted', 'reviewing', 'changes', 'scheduled', 'posted')
        join public.campaigns k on k.id = o.campaign_id
        join public.clients c on c.id = k.client_id
       where p_key ~ '^[A-Za-z0-9]{8}$'
         and cr.access_code = upper(p_key) and cr.active)
  end, '{}'::jsonb)
$$;
revoke all on function public.share_link_preview(text, text) from public;
grant execute on function public.share_link_preview(text, text) to anon, authenticated;

-- END OF SHORT LINKS RE-LETTERED --------------------------------------------
select public.functions_tidy();
