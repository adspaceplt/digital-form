-- ===========================================================================
-- OUTSTATION LINK ON HI.ADSPACE.ME (2026-11-26)
-- ===========================================================================
-- WHY: go.adspace.me is being phased out (2026-11-26); the outstation
-- reminder still linked https://go.adspace.me/outstation. The user: "move
-- the outstation link to hi.adspace.me/outstation", the short link the team
-- keeps under Short Links, which opens the portal's Outstation.
--
-- WHAT IT CHANGES
--   * `ops_outstation_remind()`: the reminder's link is
--     https://hi.adspace.me/outstation. Everything else stands.
--   * Reminders already sent (`ops_notifications`, kind `outstation`) that
--     still carry the go.adspace.me link take the new one.
--
-- ORDER: this file alone; no page reads the address. Safe to run twice.
-- Holds no drop or delete.
-- ROLLBACK: run COLLEAGUE LEAVING's `ops_outstation_remind()` again, and
-- set the link back on the rows this file moved.
-- ===========================================================================

-- OUTSTATION LINK ON HI.ADSPACE.ME -----------------------------------------

create or replace function public.ops_outstation_remind()
returns integer
language plpgsql security definer set search_path = public as $$
declare r record; n integer := 0;
begin
  for r in
    select e.id, e.meeting_at, coalesce(e.meeting_owner_id, e.manager_id) as who, c.name as client_name
      from public.ops_engagements e
      left join public.clients c on c.id = e.client_id
     where e.meeting_channel = 'onsite' and not e.meeting_na and e.meeting_at is not null
       and e.outstation_told_at is null
       and e.meeting_at + make_interval(mins => coalesce(e.meeting_minutes, 30)) <= now()
       and coalesce(e.status, '') <> 'cancelled'
     for update of e skip locked
  loop
    if r.who is not null and exists (select 1 from public.team_members t where t.id = r.who and t.active) then
      insert into public.ops_notifications (team_member_id, kind, title, body, link, dedupe_key)
      values (r.who, 'outstation', 'Submit the outstation record',
              coalesce(r.client_name, 'Client') || ' · on-site meeting on ' ||
                public.register_day((r.meeting_at at time zone 'Asia/Kuala_Lumpur')::date),
              'https://hi.adspace.me/outstation',
              'outstation.' || r.id::text || '.' || extract(epoch from r.meeting_at)::bigint::text)
      on conflict (dedupe_key) do nothing;
      n := n + 1;
    end if;
    update public.ops_engagements set outstation_told_at = now() where id = r.id;
  end loop;
  return n;
end $$;
revoke all on function public.ops_outstation_remind() from public, anon, authenticated;

update public.ops_notifications
   set link = 'https://hi.adspace.me/outstation'
 where kind = 'outstation' and link = 'https://go.adspace.me/outstation';

-- END OF OUTSTATION LINK ON HI.ADSPACE.ME ----------------------------------
