-- INVOICE EMAIL WORDING, PREVIEW (2026-11-04): reads and writes nothing;
-- reports whether 2026-11-04-invoice-email-wording.sql will change the
-- invoice email's message.
select part, case when cur = seed then 'will change' when cur = next then 'already'
                  else 'edited in the console, left alone' end as outcome
  from public.invoice_send_template x,
  lateral (values
    ('Message', x.body, E'Dear {contact name},\n\nPlease find below the details of invoice {invoice no} for {client}, with a total of {total} due.\n\n{invoices}\n\nThe invoice may be viewed and downloaded through View PDF. Kindly arrange payment by the due date.\n\nShould you have any questions, please reply to this email.\n\nThank you for your continued support.\n\n{sign off},\nADspace Finance', E'Dear {contact name},\n\nPlease find below invoice {invoice no} for {client}, amounting to {total}.\n\n{invoices}\n\nTo view or download the invoice, please select View PDF above. Kindly arrange payment by the due date.\n\nShould you have any questions, please reply to this email.\n\nThank you for your continued support.\n\n{sign off},\nADspace Finance')
  ) v (part, cur, seed, next)
 where x.id = 1;
