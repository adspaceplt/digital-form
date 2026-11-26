-- ===========================================================================
-- QUOTATION COVER WORDS (2026-11-26)
-- ===========================================================================
-- WHY: the unslop pass (2026-11-26, PDF item 4): the Quotation Cover is page 1
-- of the quotation's own PDF, so "set out in the attached quotation" misread,
-- and its closing paragraph was boilerplate.
--
-- WHAT IT CHANGES
--   * `doc_types` `quote_cover`: `body_en` reads "…set out in the following
--     pages." and drops its last paragraph, only where it still holds the
--     seeded words (a type the team edited is kept).
--
-- ORDER: the page first (its stand-in words change with it), then this file.
-- Safe to run twice. Holds no drop or delete.
-- ROLLBACK: set `body_en` back to the seeded words in DOCUMENT TYPES.
-- ===========================================================================

-- QUOTATION COVER WORDS -------------------------------------------------------

-- The seeded words, as they stood, take the page's: the details are on the
-- following pages of the same PDF, and the closing paragraph goes. A type the
-- team has edited is left as it is.
update public.doc_types
   set body_en = E'We are pleased to submit our quotation for your consideration. It has been prepared based on the scope and requirements discussed, with full details set out in the following pages.\n\nShould you need any clarification or additional information, please do not hesitate to contact us. We would be pleased to provide further materials to support your evaluation.'
 where id = 'quote_cover'
   and body_en = E'We are pleased to submit our quotation for your consideration. It has been prepared based on the scope and requirements discussed, with full details set out in the attached quotation.\n\nShould you need any clarification or additional information, please do not hesitate to reach out. We are happy to provide further materials to support your evaluation.\n\nThank you for the opportunity. We look forward to working with you and your team.';

-- END OF QUOTATION COVER WORDS ------------------------------------------------
