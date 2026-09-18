-- 2026-09-22  The document kinds are named the way the team names them.
--
-- Quotation Cover, Thank You Letter, Letter to Client, Confirmation of
-- Employment, HR Letter: the user's own list, as a form is named. The kind
-- is seeded once into doc_types and copied onto every document at issue, so
-- both are renamed here; a kind the team has since renamed itself is left
-- alone, because only the seeded spellings are matched. Safe to run twice.
--
-- POST-MIGRATION VERIFICATION
--   select id, name from public.doc_types order by position;
--
-- ROLLBACK
--   Run the updates below with the two names swapped.

update public.doc_types set name = 'Quotation Cover'            where name = 'Quotation cover';
update public.doc_types set name = 'Thank You Letter'           where name = 'Thank-you letter';
update public.doc_types set name = 'Letter to Client'           where name = 'Letter to client';
update public.doc_types set name = 'Confirmation of Employment' where name = 'Confirmation of employment';
update public.doc_types set name = 'HR Letter'                  where name = 'HR letter';

update public.documents set kind = 'Quotation Cover'            where kind = 'Quotation cover';
update public.documents set kind = 'Thank You Letter'           where kind = 'Thank-you letter';
update public.documents set kind = 'Letter to Client'           where kind = 'Letter to client';
update public.documents set kind = 'Confirmation of Employment' where kind = 'Confirmation of employment';
update public.documents set kind = 'HR Letter'                  where kind = 'HR letter';
