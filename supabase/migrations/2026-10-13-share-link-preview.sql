-- ===========================================================================
-- SHARE LINK PREVIEW — the words a chat app shows for a client's Video
-- Scripts link, a campaign's creator selection link and a creator's own
-- link, each sent as a short link on the links host.
-- 2026-10-13. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-10-12: "video script and creator campaigns and
-- creator portal are not changed to hi.adspace.me … so we can show client
-- brand name instead"; the client portal left as it is)
--   1. `share_link_preview(p_kind, p_key)` answers, for a key a page would
--      open, what its preview may name and nothing more:
--        `script`   a client's Video Scripts key (`clients.script_key`, the
--                   client active, a script published): `brand`;
--        `campaign` a campaign's selection key (no passcode, not a draft):
--                   `brand` and `title`;
--        `creator`  a creator's code (the creator active) with one open
--                   booking: that campaign's `brand` and `title`; with none
--                   or several, nothing.
--      Else nothing. The links Worker (hi.adspace.me/s/, /c/, /p/) asks it
--      with the public key to fill the preview, and sends people on to the
--      page itself. Nothing is stored: the short link is the key the link
--      already carried. Joins `open_to_anon`: run
--      2026-10-07-function-hygiene.sql again BEFORE this file.
--
-- ORDER
--   2026-10-07-function-hygiene.sql, this file, then the pages (Copy link
--   builds the short link), then the Worker. A short link sent before the
--   Worker is updated answers Link not recognised, so the Worker goes live
--   the same day.
--
-- ROLLBACK
--   drop function if exists public.share_link_preview(text, text);
--   then 2026-10-07-function-hygiene.sql from before this date.
-- ===========================================================================

create or replace function public.share_link_preview(p_kind text, p_key text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(case p_kind
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

-- END OF SHARE LINK PREVIEW --------------------------------------------------

select public.functions_tidy();
