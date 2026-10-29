-- OVERDUE REMINDER WORDING, PREVIEW (2026-10-29): reads and writes nothing;
-- reports for each part of the reminder whether
-- 2026-10-29-overdue-reminder-wording.sql will change it.
select part, case when cur = seed then 'will change' when cur = next then 'already'
                  else 'edited in the console, left alone' end as outcome
  from public.invoice_email_template x,
  lateral (values
    ('Message', x.body, E'Dear {contact name},\n\nThis is a reminder that payment of {total} for {client} is now overdue.\n\n{invoices}\n\nWe would be grateful if payment could be arranged at your earliest convenience. If payment has already been made, please disregard this email.\n\nShould you have any questions, please reply to this email.\n\nThank you for your continued support.\n\n{sign off},\nADspace Finance', E'Dear {contact name},\n\nThis is a reminder that payment of {total} due from {client} is now overdue.\n\n{invoices}\n\nWe would be grateful if payment could be arranged at your earliest convenience. If payment has already been made, please disregard this email.\n\nShould you have any questions, please reply to this email.\n\nThank you for your continued support.\n\n{sign off},\nADspace Finance'),
    ('Legal note', x.legal, 'Legal note: All services rendered will be invoiced accordingly unless a written cancellation is provided and acknowledged in advance. All invoices must be settled promptly to avoid overdue interest charges.', 'Legal note: All services rendered will be invoiced accordingly unless a written cancellation is provided and acknowledged in advance. All invoices are to be settled in accordance with the agreed payment terms.'),
    ('Disclaimer', x.disclaimer, 'This email and any attachment are private and confidential and intended solely for the addressee. If you have received it in error, please notify einvoice@adspacestudios.com and delete it. Any use, copying or disclosure by anyone else is not permitted.', 'This email and any attachments are confidential and may be privileged. If you are not the intended recipient, please do not disclose, copy or rely on it; notify the sender and delete it from your system.')
  ) v (part, cur, seed, next)
 where x.id = 1;
