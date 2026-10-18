-- ===========================================================================
-- A CLIENT'S DEVICE FOLLOWS ONLY A LINK THAT OPENS — push_target refuses a
-- campaign behind a passcode and a Past client's (2026-10-18)
-- ===========================================================================
-- WHY (audit 2026-10-18, item 5): the client branch matched the link key
-- alone, so anyone holding a campaign's key could have a device told of its
-- drafts and posts without the passcode `get_campaign` asks for, and after
-- the client went Past, when `get_campaign` answers `not-found`.
--
-- WHAT IT CHANGES
--   * The client branch finds the campaign only where it has no passcode
--     and its client is not Past; anything else answers no campaign, which
--     `push_subscribe` reads as `not-found`, as the selection page itself
--     does. A campaign with a passcode offers no notifications (none held
--     one on 2026-10-18).
--   * The team and creator branches do not move.
--
-- ORDER: this file; the page needs nothing. Safe to run twice.
-- Rollback: PUSH NOTIFICATIONS' `push_target`.
-- ===========================================================================

create or replace function public.push_target(p_audience text, p_ref text)
returns uuid
language plpgsql stable security definer set search_path = public as $$
declare
  v_code text := upper(regexp_replace(coalesce(p_ref, ''), '[^A-Za-z0-9]', '', 'g'));
  v_id   uuid;
begin
  if p_audience = 'team' then
    return (public.ops_me()).id;
  elsif p_audience = 'client' and coalesce(p_ref, '') <> '' then
    -- The key alone opens only a link with no passcode, of a client not
    -- Past (audit 2026-10-18, item 5).
    select c.id into v_id from public.campaigns c
     where c.access_token = p_ref and coalesce(c.passcode, '') = ''
       and not exists (select 1 from public.clients cl where cl.id = c.client_id and cl.stage = 'past');
  elsif p_audience = 'creator' and length(v_code) >= 8 then
    select k.id into v_id from public.creators k where k.access_code = v_code and k.active;
  end if;
  return v_id;
end $$;
revoke all on function public.push_target(text, text) from public, anon, authenticated;
-- END OF A CLIENT'S DEVICE FOLLOWS ONLY A LINK THAT OPENS -------------------

select public.functions_tidy();
