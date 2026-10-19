-- ===========================================================================
-- CONTENT REVIEW BY HAND — a new client starts outside Content Review.
-- 2026-10-19. Safe to run twice. Rollback at the foot. Mirrored byte for
-- byte in supabase/schema.sql under the same banner; tests/sql.js compares
-- the two.
--
-- WHAT CHANGED (the user, 2026-10-19: "not all new leads or clients auto
-- open the content review make it manually")
--   `clients.review_hidden` defaults to true, so a lead or client added from
--   now (by hand, by the quotation website, by any insert) is out of
--   Content Review until a colleague enables it (Enable client in Content
--   Review, or Enable Content Review on the record). Every client standing
--   today keeps its place.
--
-- ROLLBACK
--   alter table public.clients alter column review_hidden set default false;
-- ===========================================================================

alter table public.clients alter column review_hidden set default true;

-- END OF CONTENT REVIEW BY HAND ---------------------------------------------
