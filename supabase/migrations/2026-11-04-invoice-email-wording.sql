-- ===========================================================================
-- INVOICE EMAIL WORDING — the invoice email reads as a letter writes it
-- (2026-11-04)
-- ===========================================================================
-- WHY (the review of the Messages section and its emails, 2026-11-04; the
-- user: "check the tone etc. for the new Messages section together with its
-- email"): "with a total of {total} due" and "may be viewed and downloaded
-- through View PDF" read as a system wrote them, not a finance team.
--
-- WHAT IT CHANGES
--   * `invoice_send_template`: the message reads "Please find below invoice
--     {invoice no} for {client}, amounting to {total}." and "To view or
--     download the invoice, please select View PDF above." Changed only
--     where it still holds the seed's words: wording a colleague changed in
--     Settings, Templates: Invoice email is left as it is (the preview file
--     reports which).
--
-- ORDER: this file alone (connector); no page reads the seed. Safe to run
-- twice.
--
-- ROLLBACK: the seed written back where the message holds this file's words.
-- ===========================================================================

update public.invoice_send_template x set body =
  E'Dear {contact name},\n\nPlease find below invoice {invoice no} for {client}, amounting to {total}.\n\n{invoices}\n\nTo view or download the invoice, please select View PDF above. Kindly arrange payment by the due date.\n\nShould you have any questions, please reply to this email.\n\nThank you for your continued support.\n\n{sign off},\nADspace Finance',
  updated_at = now()
 where x.id = 1 and x.body =
  E'Dear {contact name},\n\nPlease find below the details of invoice {invoice no} for {client}, with a total of {total} due.\n\n{invoices}\n\nThe invoice may be viewed and downloaded through View PDF. Kindly arrange payment by the due date.\n\nShould you have any questions, please reply to this email.\n\nThank you for your continued support.\n\n{sign off},\nADspace Finance';

-- END OF INVOICE EMAIL WORDING -----------------------------------------------

select public.functions_tidy();
