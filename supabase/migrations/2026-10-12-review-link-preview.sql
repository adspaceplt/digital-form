-- ===========================================================================
-- REVIEW LINK PREVIEW — the words a chat app shows for a client's review
-- link sent as a short link: the content set and the brand.
-- 2026-10-12. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/links.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-10-12: "is it possible to do dynamic title:
-- {Content Set} {client brand name} - Content Review Portal by ADspace")
--   1. `review_link_preview(p_key, p_set)` answers, for a live review key
--      (the client active, shown in Content Review, no passcode), the
--      client's name as `brand` and, where `p_set` is the first eight
--      characters of a published set's id, that set's title as `set`;
--      else nothing. The links Worker (hi.adspace.me/r/{key}/{set}) asks it
--      with the public key to fill the preview, and sends people on to the
--      review page. Nothing is stored: a short link is the key and the set,
--      so there is nothing to clean up. It says no more than the link
--      already opens. Joins `open_to_anon`: run
--      2026-10-07-function-hygiene.sql again BEFORE this file.
--
-- ORDER
--   This file, then the pages (Copy link builds the short link), then the
--   Worker. A Worker without the function answers every preview with the
--   plain title.
--
-- ROLLBACK
--   drop function if exists public.review_link_preview(text, text);
--   then 2026-10-07-function-hygiene.sql from before this date.
-- ===========================================================================

create or replace function public.review_link_preview(p_key text, p_set text default null)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select jsonb_strip_nulls(jsonb_build_object(
      'brand', c.name,
      'set', (select b.title
                from public.batches b
               where b.client_id = c.id and b.published
                 and p_set ~ '^[0-9a-f]{8}$'
                 and left(b.id::text, 8) = p_set
               order by b.created_at desc
               limit 1)))
      from public.clients c
     where p_key ~ '^[A-Za-z0-9_-]{6,64}$'
       and c.access_token = p_key and c.active
       and not c.review_hidden and c.passcode is null
     limit 1), '{}'::jsonb)
$$;
revoke all on function public.review_link_preview(text, text) from public;
grant execute on function public.review_link_preview(text, text) to anon, authenticated;

-- END OF REVIEW LINK PREVIEW -------------------------------------------------

select public.functions_tidy();
