-- ===========================================================================
-- AI RUNS COUNTED AS THEY RAN — a use of Write with AI that reached the
-- model counts against the day's limits however it ended. 2026-10-17. Safe
-- to run twice. Rollback at the foot. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the security audit of 2026-10-16, finding G; the user:
-- "count every failure except rejected")
--   Every daily limit (`ai_draft_claim`, `ai_check_claim`, `ai_caption_claim`,
--   `ai_script_claim`, `ai_analysis_claim`, `ai_checklist_claim` and their
--   `_left` reads) counts the rows whose outcome is not `failed`, and the
--   edge functions marked a run failed whenever it ended without a usable
--   answer: one stopped at its length (max_tokens), refused, answered with
--   no draft in it, or a brand analysis that ran out of turns. Those runs
--   had used the model, and were free, so the limit held nothing back.
--   1. A run is `incomplete` when it ended without an answer after the
--      model had read it: its tokens are kept (`ai_draft_tokens`, input
--      above nought) on its row. `ai_draft_done` with no answer marks such a
--      row `incomplete`, and `ai_draft_tokens` turns a row already marked
--      `failed` into `incomplete` when its tokens arrive after (report-draft
--      keeps them last). `incomplete` is not `failed`, so every limit counts
--      it, untouched.
--   2. A request the API refused before it generated (an HTTP error, the
--      service busy, a bad key) keeps no tokens, stays `failed` and is not
--      counted, as before.
--   No edge function changes: each already keeps a run's tokens whenever
--   the model answered, and nought when it did not.
--
-- ROLLBACK
--   Run ai_draft_done and ai_draft_tokens again from their sections as they
--   stood before 2026-10-17; `update public.ai_drafts set outcome = 'failed'
--   where outcome = 'incomplete'`, then put the check back to its three
--   outcomes.
-- ===========================================================================

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'ai_drafts_outcome' and pg_get_constraintdef(oid) like '%incomplete%') then
    alter table public.ai_drafts drop constraint if exists ai_drafts_outcome;
    alter table public.ai_drafts add constraint ai_drafts_outcome
      check (outcome in ('pending', 'drafted', 'incomplete', 'failed'));
  end if;
end $$;

create or replace function public.ai_draft_done(p_id uuid, p_ok boolean)
returns void
language sql security definer set search_path = public as $$
  update public.ai_drafts d
     set outcome = case when p_ok then 'drafted'
                        when coalesce(d.input_tokens, 0) > 0 then 'incomplete'
                        else 'failed' end
   where d.id = p_id and d.outcome = 'pending'
     and d.team_member_id = (public.ops_me()).id
$$;

create or replace function public.ai_draft_tokens(p_id uuid, p_in integer, p_out integer, p_model text)
returns void
language sql security definer set search_path = public as $$
  update public.ai_drafts d
     set input_tokens = greatest(0, coalesce(p_in, 0)),
         output_tokens = greatest(0, coalesce(p_out, 0)),
         model = left(nullif(btrim(coalesce(p_model, '')), ''), 80),
         outcome = case when d.outcome = 'failed' and coalesce(p_in, 0) > 0 then 'incomplete' else d.outcome end
   where d.id = p_id and d.input_tokens is null
     and d.team_member_id = (public.ops_me()).id
$$;

-- END OF AI RUNS COUNTED AS THEY RAN -----------------------------------------

select public.functions_tidy();
