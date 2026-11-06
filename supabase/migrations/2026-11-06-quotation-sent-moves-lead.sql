-- ===========================================================================
-- A QUOTATION SENT MOVES ITS LEAD TO PROPOSAL SENT (2026-11-06)
-- ===========================================================================
-- WHY (the user, 2026-11-06): "An quotation alr sent out, the status not
-- changed automatically (Contacted)".
--
-- WHAT IT CHANGES
--   Once the portal sends a quotation out (`quotations.sent_out_at` first
--   stamped: a website quotation released, a team's given its link, or a
--   WhatsApp or email filed for it), a client at Lead or Contacted moves to
--   Proposal sent, the stage clock stamping the move, filed `client.stage`
--   Proposal sent · {ref} sent out. A fault never fails the send. A client
--   past those stages is left as it is. Leads already sent one move once.
--
-- ORDER: this file alone; no page changes for it. Safe to run twice.
--
-- ROLLBACK: drop trigger quotations_sent_moves_lead on public.quotations;
-- drop function public.quotations_sent_moves_lead(). The backfilled stages
-- stay; move them back by hand if wanted.
-- ===========================================================================

-- A QUOTATION SENT MOVES ITS LEAD -------------------------------------------

create or replace function public.quotations_sent_moves_lead()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_c public.clients;
  v_me public.team_members;
begin
  if new.sent_out_at is null or (tg_op = 'UPDATE' and old.sent_out_at is not null) or new.removed_at is not null then
    return null;
  end if;
  update public.clients x set stage = 'proposal'
   where x.id = new.client_id and x.stage in ('lead', 'contacted')
  returning * into v_c;
  if v_c.id is not null then
    v_me := public.ops_me();
    insert into public.activity_log (actor, action, subject, detail)
    values (coalesce(v_me.name, 'ADspace'), 'client.stage', v_c.name, 'Proposal sent · ' || new.ref || ' sent out');
  end if;
  return null;
exception when others then
  raise warning 'quotations_sent_moves_lead: %', sqlerrm;
  return null;
end $$;
revoke all on function public.quotations_sent_moves_lead() from public, anon, authenticated;
create or replace trigger quotations_sent_moves_lead after insert or update of sent_out_at on public.quotations
  for each row execute function public.quotations_sent_moves_lead();

-- Leads already sent a quotation move once.
with moved as (
  update public.clients c set stage = 'proposal'
   where c.stage in ('lead', 'contacted')
     and exists (select 1 from public.quotations q
                  where q.client_id = c.id and q.sent_out_at is not null and q.removed_at is null)
  returning c.id, c.name)
insert into public.activity_log (actor, action, subject, detail)
select 'ADspace', 'client.stage', m.name,
       'Proposal sent · ' || (select q.ref from public.quotations q where q.client_id = m.id and q.sent_out_at is not null
                                and q.removed_at is null order by q.sent_out_at limit 1) || ' sent out'
  from moved m;

-- END OF A QUOTATION SENT MOVES ITS LEAD ------------------------------------

select public.functions_tidy();
