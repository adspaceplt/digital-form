-- ===========================================================================
-- PROPOSAL SENT FROM EVERY ROUTE (2026-11-06)
-- ===========================================================================
-- WHY (review of A QUOTATION SENT MOVES ITS LEAD, the user: "Go ahead all
-- fixes"): that trigger ran only on `update of sent_out_at`, which a release
-- or a signing link never names (a BEFORE trigger stamps it), so Send
-- quotation, Publish and a signing link left the lead at Contacted; a
-- quotation signed on paper before it was sent, and a Letter of Offer
-- issued, moved nothing.
--
-- WHAT IT CHANGES
--   client_proposal_sent(client, detail): the one move, Lead or Contacted to
--   Proposal sent, filed `client.stage` Proposal sent · {detail}.
--   quotations_sent_moves_lead now runs on every insert and update, moving
--   on the first sent_out_at or signed_at; client_documents_moves_lead on a
--   Letter of Offer issued. A fault never fails the write. Leads already
--   sent, signed or issued one move once.
--
-- ORDER: this file alone; no page changes for it. Safe to run twice.
--
-- ROLLBACK: drop trigger client_documents_moves_lead on
-- public.client_documents; run A QUOTATION SENT MOVES ITS LEAD again; drop
-- function public.client_documents_moves_lead() and
-- public.client_proposal_sent(uuid, text). Moved stages stay.
-- ===========================================================================

-- PROPOSAL SENT FROM EVERY ROUTE --------------------------------------------

-- The one move: a Lead or Contacted client to Proposal sent, filed once.
create or replace function public.client_proposal_sent(p_client uuid, p_detail text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_c public.clients;
  v_me public.team_members;
begin
  update public.clients x set stage = 'proposal'
   where x.id = p_client and x.stage in ('lead', 'contacted')
  returning * into v_c;
  if v_c.id is null then return; end if;
  v_me := public.ops_me();
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_me.name, 'ADspace'), 'client.stage', v_c.name, 'Proposal sent · ' || p_detail);
end $$;
revoke all on function public.client_proposal_sent(uuid, text) from public, anon, authenticated;

-- A quotation sent out or signed. No column list: a release or a signing
-- link stamps sent_out_at in a BEFORE trigger, which an `update of` trigger
-- never sees (2026-11-06 review).
create or replace function public.quotations_sent_moves_lead()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.removed_at is not null or (new.sent_out_at is null and new.signed_at is null) then return null; end if;
  if tg_op = 'UPDATE' and (old.sent_out_at is not null or old.signed_at is not null) then return null; end if;
  perform public.client_proposal_sent(new.client_id,
    new.ref || case when new.sent_out_at is not null then ' sent out' else ' signed' end);
  return null;
exception when others then
  raise warning 'quotations_sent_moves_lead: %', sqlerrm;
  return null;
end $$;
revoke all on function public.quotations_sent_moves_lead() from public, anon, authenticated;
create or replace trigger quotations_sent_moves_lead after insert or update on public.quotations
  for each row execute function public.quotations_sent_moves_lead();

-- A Letter of Offer issued (a preview's insert rolls back with it).
create or replace function public.client_documents_moves_lead()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind is distinct from 'offer' or new.voided_at is not null then return null; end if;
  perform public.client_proposal_sent(new.client_id, new.number || ' issued');
  return null;
exception when others then
  raise warning 'client_documents_moves_lead: %', sqlerrm;
  return null;
end $$;
revoke all on function public.client_documents_moves_lead() from public, anon, authenticated;
create or replace trigger client_documents_moves_lead after insert on public.client_documents
  for each row execute function public.client_documents_moves_lead();

-- Leads already sent or signed a quotation, or issued a letter, move once.
do $$
declare r record;
begin
  for r in
    select c.id,
           coalesce((select q.ref || case when q.sent_out_at is not null then ' sent out' else ' signed' end
                       from public.quotations q
                      where q.client_id = c.id and q.removed_at is null
                        and (q.sent_out_at is not null or q.signed_at is not null)
                      order by coalesce(q.sent_out_at, q.signed_at) limit 1),
                    (select d.number || ' issued' from public.client_documents d
                      where d.client_id = c.id and d.kind = 'offer' and d.voided_at is null
                      order by d.created_at limit 1)) as detail
      from public.clients c
     where c.stage in ('lead', 'contacted')
  loop
    if r.detail is not null then perform public.client_proposal_sent(r.id, r.detail); end if;
  end loop;
end $$;

-- END OF PROPOSAL SENT FROM EVERY ROUTE -------------------------------------

select public.functions_tidy();
