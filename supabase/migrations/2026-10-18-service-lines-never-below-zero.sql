-- ===========================================================================
-- SERVICE LINES NEVER BELOW ZERO — a client's service line holds no
-- negative rate or quantity. 2026-10-18. Safe to run twice. Rollback at the
-- foot. Mirrored byte for byte in supabase/schema.sql under the same banner;
-- tests/sql.js compares the two.
--
-- WHAT CHANGED
--   client_services.rate and qty took any number, and the Services sheet
--   sent what was typed. Since QUOTE TOTALS IN ONE PLACE (#563) a letter's
--   one-off part that adds up to zero or less is left out by quote_totals
--   while the page keeps it, so a letter holding a negative line was
--   refused `stale` on every press of Issue. Both columns now refuse a
--   figure below zero (client_services_rate_check, client_services_qty_check;
--   none of the 17 live lines held one, 2026-10-18), and the sheet refuses
--   it in words before it is sent. A quotation's own edits already refuse
--   one (`bad-edit`).
--
-- ROLLBACK
--   alter table public.client_services drop constraint if exists client_services_rate_check;
--   alter table public.client_services drop constraint if exists client_services_qty_check;
-- ===========================================================================

do $$
begin
  if exists (select 1 from public.client_services where rate < 0 or qty < 0) then
    raise exception 'client_services holds a negative rate or quantity: correct those lines first'
      using hint = 'select id, client_id, label, qty, rate from public.client_services where rate < 0 or qty < 0;';
  end if;
  if not exists (select 1 from pg_constraint where conname = 'client_services_rate_check'
                    and conrelid = 'public.client_services'::regclass) then
    alter table public.client_services add constraint client_services_rate_check check (rate >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'client_services_qty_check'
                    and conrelid = 'public.client_services'::regclass) then
    alter table public.client_services add constraint client_services_qty_check check (qty >= 0);
  end if;
end $$;

-- END OF SERVICE LINES NEVER BELOW ZERO -------------------------------------

select public.functions_tidy();
