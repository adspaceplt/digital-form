-- ===========================================================================
-- LETTER PRICED AS ITS QUOTATION — the quotation's rate and term for a
-- colleague who issues letters but cannot read quotations (2026-10-26)
-- ===========================================================================
-- WHY (the whole-repo audit of 2026-10-26, finding 2): `issue_letter` prices
-- a letter whose every line came from one standing quotation at that
-- quotation's SST rate and term. The page priced it the same way only where
-- it had read the quotation (Clients: Quotations at View). A colleague at
-- Clients: Letters Work without it priced the lines one by one, so every
-- press was refused `stale` and the sheet read the same lines again.
--
-- WHAT IT ADDS
--   `letter_quote_terms(p_services)`: for the lines a letter is about to
--   hold, where all came from one quotation, that quotation's id, its
--   validity, whether it was removed, and the two figures the price reads
--   (`totals.sst_pct`, `totals.term`); nothing else of it. Asked at
--   Clients: Letters Work (as `issue_letter` asks) on a client the caller's
--   scope reaches; anything else answers null.
--
-- ORDER: this file (connector), then the pages. A page served before it
-- never asks; one served after it on a database without it reads an error
-- and prices as before.
--
-- ROLLBACK: pages first; then drop function public.letter_quote_terms(uuid[]).
-- ===========================================================================

create or replace function public.letter_quote_terms(p_services uuid[])
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_qid uuid;
  v_n int;
  q public.quotations;
begin
  if not public.allowed('clients.documents') or p_services is null then return null; end if;
  select count(*), min(cs.quotation_id::text)::uuid
    into v_n, v_qid
    from public.client_services cs
   where cs.id = any(p_services)
  having count(*) filter (where cs.quotation_id is null) = 0
     and count(distinct cs.quotation_id) = 1;
  if v_qid is null then return null; end if;
  select * into q from public.quotations x where x.id = v_qid;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'view') then return null; end if;
  return jsonb_build_object(
    'id', q.id, 'valid_until', q.valid_until, 'removed_at', q.removed_at,
    'totals', jsonb_build_object('sst_pct', q.totals->'sst_pct', 'term', q.totals->'term'));
end $$;
revoke all on function public.letter_quote_terms(uuid[]) from public, anon;
grant execute on function public.letter_quote_terms(uuid[]) to authenticated;

-- END OF LETTER PRICED AS ITS QUOTATION ---------------------------------------

select public.functions_tidy();
