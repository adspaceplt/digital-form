-- ===========================================================================
-- CHECKLISTS FOR REACH — four checks on Reels and three on Graphics against
-- low views and restricted accounts, before a piece goes to AQC review.
-- 2026-10-10. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js runs it twice.
-- Run supabase/migrations/2026-10-10-checklists-for-reach-preview.sql first.
--
-- WHAT CHANGED (the user, 2026-10-09: "social media contents doesn't have
-- high views, account restricted, content not interesting")
--   1. Each line is appended to its template's checklist only where the
--      template still holds it nowhere, so a line the team already added,
--      renamed or removed by hand is never put back twice; nothing already
--      there is moved or changed. Tasks made before keep their own lists.
--
-- ROLLBACK
--   Remove the lines in My Work, Templates. Nothing else reads them.
-- ===========================================================================

do $$
declare
  want record;
begin
  for want in
    select * from (values
      ('Reels',    1, 'Hook lands in the first 3 seconds'),
      ('Reels',    2, 'Music licensed for business use'),
      ('Reels',    3, 'Original footage, no reused or watermarked clips'),
      ('Reels',    4, 'No absolute claims; prices and offers checked against the brief'),
      ('Graphics', 1, 'Headline reads at a glance on a phone'),
      ('Graphics', 2, 'Images and fonts licensed, no watermarks'),
      ('Graphics', 3, 'No absolute claims; prices and offers checked against the brief')
    ) as w(template, pos, label)
    order by template, pos
  loop
    update public.ops_task_templates t
       set checklist = coalesce(t.checklist, '[]'::jsonb) || to_jsonb(want.label),
           updated_at = now()
     where t.name = want.template
       and not coalesce(t.checklist, '[]'::jsonb) @> to_jsonb(array[want.label]);
  end loop;
end $$;

-- END OF CHECKLISTS FOR REACH -------------------------------------------------
