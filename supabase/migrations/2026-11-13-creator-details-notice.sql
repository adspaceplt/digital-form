-- ===========================================================================
-- CREATOR DETAILS NOTICE — the team is told when a creator sends payment
-- details to review (2026-11-13)
-- ===========================================================================
-- WHY (the user, 2026-11-13: "when creator submitted payment, it doesnt
-- prompt notification … i had the email accidentally not on, and we didnt
-- even know new payment being submitted"): a set of payment details sent on
-- the creator's page told the finance address by email alone, which
-- Automatic emails off stopped.
--
-- WHAT CHANGED
--   * Trigger `creator_pay_requests_notice`: a set filed waiting for a
--     decision (status pending, as the creator's page files it) tells every
--     active colleague of the Marketing department who can open the
--     Creators List (the user, 2026-11-13: "these should land to Marketing
--     Department personnel"; never a system account) in the bell and on
--     their phone, kind
--     `creator.details`, opening the creator's Payment pane. One notice a
--     set a colleague (`dedupe_key`); a fault never fails the creator's send.
--
-- ORDER: this file (connector), then the pages. Safe to run twice.
--
-- ROLLBACK: drop trigger creator_pay_requests_notice on
-- public.creator_pay_requests; drop function public.creator_pay_requests_notice();
-- ===========================================================================

-- CREATOR DETAILS NOTICE ----------------------------------------------------

create or replace function public.creator_pay_requests_notice()
returns trigger
language plpgsql security definer set search_path = public as $$
declare c public.creators;
begin
  if new.status is distinct from 'pending' then return null; end if;
  begin
    select * into c from public.creators x where x.id = new.creator_id;
    insert into public.ops_notifications (team_member_id, kind, title, body, link, dedupe_key)
    select tm.id, 'creator.details', 'Payment details to review · ' || coalesce(c.name, new.ref),
           new.ref || ' · Sent on the creator page',
           'https://digital.adspace.me/admin/?s=campaigns&tab=roster&pay=' || new.creator_id,
           'creator.details:' || new.id || ':' || tm.id
      from public.team_members tm
     where tm.active and tm.removed_at is null and not coalesce(tm.system, false)
       and tm.department = 'marketing'
       and (tm.is_admin or tm.role = 'admin'
            or public.level_rank(coalesce(tm.access ->> 'campaigns.creators', tm.access ->> 'campaigns')) >= 1)
    on conflict (dedupe_key) do nothing;
  exception when others then
    return null;
  end;
  return null;
end $$;
revoke all on function public.creator_pay_requests_notice() from public, anon, authenticated;
create or replace trigger creator_pay_requests_notice after insert on public.creator_pay_requests
  for each row execute function public.creator_pay_requests_notice();

-- END OF CREATOR DETAILS NOTICE ---------------------------------------------

select public.functions_tidy();
