-- Checklists for reach, 2026-10-10: what the checklist migration would add.
-- READ ONLY. Run this first, in the SQL editor, before
-- supabase/migrations/2026-10-10-checklists-for-reach.sql.
--
-- One row per line that migration names: `will be added` where its template
-- holds it nowhere, `already` where it does, `template not found` where no
-- template carries that name (renamed in the console, so left alone).
with want (template, pos, label) as (values
  ('Reels',    1, 'Hook lands in the first 3 seconds'),
  ('Reels',    2, 'Music licensed for business use'),
  ('Reels',    3, 'Original footage, no reused or watermarked clips'),
  ('Reels',    4, 'No absolute claims; prices and offers checked against the brief'),
  ('Graphics', 1, 'Headline reads at a glance on a phone'),
  ('Graphics', 2, 'Images and fonts licensed, no watermarks'),
  ('Graphics', 3, 'No absolute claims; prices and offers checked against the brief')
)
select w.template, w.label,
       case when t.id is null then 'template not found'
            when coalesce(t.checklist, '[]'::jsonb) @> to_jsonb(array[w.label]) then 'already'
            else 'will be added' end as outcome
  from want w
  left join public.ops_task_templates t on t.name = w.template
 order by w.template, w.pos;
