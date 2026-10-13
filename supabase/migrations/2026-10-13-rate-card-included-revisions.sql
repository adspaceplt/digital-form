-- ===========================================================================
-- RATE CARD INCLUDED REVISIONS — the Add-ons table opens on the revisions a
-- deliverable already carries (2026-10-13)
-- ===========================================================================
-- WHY
--   The rate card's Add-ons table reads first "Included revisions ·
--   Included · 2 rounds per asset", a fact that is no line of the price
--   list. It is a block of the card's wording (`addons_included`, Item |
--   Rate | Unit), edited in Services, Wording, and printed by the rate card
--   PDF. Version 2.0.6, published before the block existed, is the card as
--   issued, so its snapshot takes the block once.
--
-- ORDER
--   This file, then the pages. A page from before never reads the block.
--
-- ROLLBACK
--   Remove the row from rate_card_text and the key from the 2.0.6
--   snapshot's text. Nothing else reads it.
-- ===========================================================================

insert into public.rate_card_text (key, label, page, position, value) values
  ('addons_included', 'Add-ons: Included row (Item | Rate | Unit)', 'Add-ons', 49,
   'Included revisions | Included | 2 rounds per asset')
on conflict (key) do nothing;

update public.rate_card_versions v
   set snapshot = jsonb_set(v.snapshot, '{text,addons_included}',
                            to_jsonb('Included revisions | Included | 2 rounds per asset'::text))
 where v.version = '2.0.6'
   and v.snapshot ? 'text'
   and not (v.snapshot->'text' ? 'addons_included');

-- END OF RATE CARD INCLUDED REVISIONS ---------------------------------------
