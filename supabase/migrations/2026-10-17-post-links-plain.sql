-- ===========================================================================
-- POST LINKS PLAIN — a creator's post link holds no character that can
-- close the attribute a page draws it in. 2026-10-17. Safe to run twice.
-- Rollback at the foot. Mirrored byte for byte in supabase/schema.sql under
-- the same banner; tests/sql.js compares the two. Runs after THE CREATOR
-- REPORTS THE RESULTS.
--
-- WHAT CHANGED (the security audit of 2026-10-16, finding 3)
--   1. `post_link_ok` (anon, asked by `creator_post_save`) took a link on
--      the platform's own host whatever else it held, so
--      `https://instagram.com/x"onmouseover="…` reached the selection page,
--      the console and the creator's page as a link. It now refuses a link
--      holding `"`, `'`, `<`, `>`, a backslash or a backtick (`link`, as any
--      other link refused). Checked live on 2026-10-17: none of the nine
--      stored post links holds one.
--
-- ROLLBACK
--   Run `post_link_ok` again from
--   2026-09-27-your-results-come-from-the-creator.sql (it reopens the
--   finding; the pages escape the quotes since 2026-10-17 regardless).
-- ===========================================================================

/* The link is the platform's own post, on its own host, and nothing else:
   the client's page opens it as "View post on {platform}". */
create or replace function public.post_link_ok(p_platform text, p_url text)
returns boolean
language plpgsql immutable set search_path = public as $$
declare
  v    text := btrim(coalesce(p_url, ''));
  host text;
begin
  if v = '' or length(v) > 500 or v ~ '\s' or v !~* '^https://' then return false; end if;
  /* Nothing that can close an attribute or open a tag (audit 2026-10-16). */
  if v ~ '["''<>`\\]' then return false; end if;
  host := lower(substring(v from '^https://([^/?#]+)'));
  if host is null or host ~ '[@:]' then return false; end if;
  host := regexp_replace(host, '^(www|m|vm|vt)\.', '');
  return case public.post_platform_key(p_platform)
    when 'xhs' then host in ('xiaohongshu.com', 'xhslink.com')
    when 'instagram' then host = 'instagram.com'
    when 'tiktok' then host = 'tiktok.com'
    when 'facebook' then host in ('facebook.com', 'fb.watch', 'fb.com')
    else true end;
end $$;
grant execute on function public.post_link_ok(text, text) to anon, authenticated;

-- END OF POST LINKS PLAIN ----------------------------------------------------

select public.functions_tidy();
