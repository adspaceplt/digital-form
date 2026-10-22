-- ===========================================================================
-- BACKEND REVIEW REST — the remaining database findings of the 2026-10-22
-- backend review (the user, 2026-10-22: "Fix all"). 2026-10-22. Safe to run
-- twice. Rollback at the foot. Mirrored byte for byte in supabase/schema.sql
-- under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED
--   BE-11. A device is never pushed out by another: `push_subscribe` takes
--     five new devices a target in any hour and twenty in all, refusing
--     `too-many` past either, where it used to drop the oldest, so a client's
--     link could no longer be used to push the client's own phones off.
--
-- ORDER: this file in the SQL Editor (`push_subscribe` holds a delete, which
--   the connector holds), then the pages. A page from before reads as it
--   did; a device refused `too-many` keeps its notifications off.
--
-- ROLLBACK
--   push_subscribe as PUSH NOTIFICATIONS defines it.
-- ===========================================================================

/* A device turns notifications on for what its page follows. A console
   follows one colleague and a creator's page one creator, so turning on
   there moves the device; a client's device adds each campaign it is turned
   on for. A device already following keeps its place; a new one is taken
   five a target in any hour and twenty in all, never by pushing another
   out (2026-10-22, BE-11). */
create or replace function public.push_subscribe(
  p_audience text, p_ref text, p_endpoint text, p_p256dh text, p_auth text, p_lang text default 'en')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_target uuid;
  v_lang   text := case when p_lang = 'zh' then 'zh' else 'en' end;
begin
  if not public.push_endpoint_ok(p_endpoint)
     or coalesce(length(p_p256dh), 0) not between 80 and 100
     or coalesce(length(p_auth), 0) not between 16 and 32 then
    return jsonb_build_object('error', 'bad-subscription');
  end if;
  if p_audience not in ('team', 'client', 'creator') then
    return jsonb_build_object('error', 'bad-audience');
  end if;
  v_target := public.push_target(p_audience, p_ref);
  if v_target is null then
    return jsonb_build_object('error', case when p_audience = 'team' then 'not-team' else 'not-found' end);
  end if;

  if not exists (select 1 from public.push_subscriptions s where s.endpoint = p_endpoint and s.target = v_target) then
    perform pg_advisory_xact_lock(hashtext('push_subscribe:' || v_target::text));
    if (select count(*) from public.push_subscriptions s
         where s.target = v_target and s.created_at > now() - interval '1 hour') >= 5
       or (select count(*) from public.push_subscriptions s where s.target = v_target) >= 20 then
      return jsonb_build_object('error', 'too-many');
    end if;
  end if;

  if p_audience in ('team', 'creator') then
    delete from public.push_subscriptions s
     where s.endpoint = p_endpoint and s.audience = p_audience and s.target <> v_target;
  end if;
  insert into public.push_subscriptions
    (endpoint, p256dh, auth, audience, team_member_id, campaign_id, creator_id, lang)
  values (p_endpoint, p_p256dh, p_auth, p_audience,
          case when p_audience = 'team' then v_target end,
          case when p_audience = 'client' then v_target end,
          case when p_audience = 'creator' then v_target end, v_lang)
  on conflict (endpoint, target) do update
     set lang = excluded.lang, seen_at = now();
  update public.push_subscriptions s set p256dh = p_p256dh, auth = p_auth
   where s.endpoint = p_endpoint and (s.p256dh <> p_p256dh or s.auth <> p_auth);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.push_subscribe(text, text, text, text, text, text) from public;
grant execute on function public.push_subscribe(text, text, text, text, text, text) to anon, authenticated;

-- END OF BACKEND REVIEW REST ------------------------------------------------

select public.functions_tidy();
