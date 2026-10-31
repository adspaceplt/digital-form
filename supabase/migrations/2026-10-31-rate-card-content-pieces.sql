-- ===========================================================================
-- RATE CARD CONTENT PIECES — the monthly packages count content pieces,
-- never contents.
-- 2026-10-31. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner.
-- Run supabase/migrations/2026-10-31-rate-card-content-pieces-preview.sql
-- first.
--
-- WHAT CHANGED (the client pages audit, POR-5, 2026-10-31: the client
-- portal read "Package B · 2 platforms · 4 contents"; content is
-- uncountable, DESIGN.md §6)
--   1. Each package's name is changed only where it still holds the name
--      the schema seeded, so a name the team corrected in the console is
--      left alone.
--   2. Each package's inclusions change one line, "N contents each month:"
--      to "N content pieces each month:", only where that line still reads
--      so; every other line, and a line the team rewrote, is left as it is.
--   The draft of the rate card changes; the live version, the quotations and
--   the letters already issued keep the words they were made with until the
--   card is published again (Services, Review changes, Publish). A client's
--   own service line keeps the label it was given when it was added.
--
-- ROLLBACK
--   update public.services s set name = v.old_name
--     from (values
--       ('pkg-a', 'Package A · 1 platform · 2 content pieces', 'Package A · 1 platform · 2 contents'),
--       ('pkg-b', 'Package B · 2 platforms · 4 content pieces', 'Package B · 2 platforms · 4 contents'),
--       ('pkg-c', 'Package C · 3 platforms · 8 content pieces', 'Package C · 3 platforms · 8 contents'),
--       ('pkg-d', 'Package D · 1 platform · 4 content pieces · ads', 'Package D · 1 platform · 4 contents · ads'),
--       ('pkg-e', 'Package E · 2 platforms · 6 content pieces · ads', 'Package E · 2 platforms · 6 contents · ads'),
--       ('pkg-f', 'Package F · 3 platforms · 10 content pieces · ads', 'Package F · 3 platforms · 10 contents · ads')
--     ) as v(slug, new_name, old_name)
--    where s.slug = v.slug and s.name = v.new_name;
--   update public.services
--      set detail = regexp_replace(detail, '(^|\n)([0-9]+) content pieces each month:', '\1\2 contents each month:', 'g')
--    where slug in ('pkg-a', 'pkg-b', 'pkg-c', 'pkg-d', 'pkg-e', 'pkg-f')
--      and detail ~ '(^|\n)[0-9]+ content pieces each month:';
-- ===========================================================================

update public.services s set name = v.new_name
  from (values
    ('pkg-a', 'Package A · 1 platform · 2 contents', 'Package A · 1 platform · 2 content pieces'),
    ('pkg-b', 'Package B · 2 platforms · 4 contents', 'Package B · 2 platforms · 4 content pieces'),
    ('pkg-c', 'Package C · 3 platforms · 8 contents', 'Package C · 3 platforms · 8 content pieces'),
    ('pkg-d', 'Package D · 1 platform · 4 contents · ads', 'Package D · 1 platform · 4 content pieces · ads'),
    ('pkg-e', 'Package E · 2 platforms · 6 contents · ads', 'Package E · 2 platforms · 6 content pieces · ads'),
    ('pkg-f', 'Package F · 3 platforms · 10 contents · ads', 'Package F · 3 platforms · 10 content pieces · ads')
  ) as v(slug, old_name, new_name)
 where s.slug = v.slug and s.name = v.old_name;

update public.services
   set detail = regexp_replace(detail, '(^|\n)([0-9]+) contents each month:', '\1\2 content pieces each month:', 'g')
 where slug in ('pkg-a', 'pkg-b', 'pkg-c', 'pkg-d', 'pkg-e', 'pkg-f')
   and detail ~ '(^|\n)[0-9]+ contents each month:';

-- END OF RATE CARD CONTENT PIECES ---------------------------------------------
