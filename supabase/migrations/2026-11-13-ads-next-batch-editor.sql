-- ===========================================================================
-- ADS NEXT BATCH, THE SQL EDITOR PART — run once in the SQL Editor before
-- ADS NEXT BATCH (2026-11-13; the connector holds a statement naming drop).
-- `ai_drafts.purpose` takes `next`: the Next batch suggestions of an
-- Advertising Report are an AI use of their own. Re-runnable.
-- Rollback: none needed; the purpose may stay.

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'ai_drafts_purpose' and pg_get_constraintdef(oid) like '%''next''%') then
    alter table public.ai_drafts drop constraint if exists ai_drafts_purpose;
    alter table public.ai_drafts add constraint ai_drafts_purpose
      check (purpose in ('draft', 'check', 'caption', 'script', 'analysis', 'checklist', 'analytics', 'picture', 'agent', 'next'));
  end if;
end $$;

-- END OF ADS NEXT BATCH, THE SQL EDITOR PART ---------------------------------
