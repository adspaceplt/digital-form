-- ===========================================================================
-- CREATORS FROM AP01, THE SQL EDITOR PART — run once in the SQL Editor
-- before CREATORS FROM AP01 (2026-11-10; the connector holds a statement
-- naming drop). An imported set of payment details may hold no billing
-- address; that migration's check keeps every other set holding one.
-- Re-runnable. Rollback: set the address on every imported set, then
-- `alter column address set not null`.

alter table public.creator_pay_requests alter column address drop not null;

-- END OF CREATORS FROM AP01, THE SQL EDITOR PART -----------------------------
