# Supplier and client emails: setup

Supplier emails, and a client's quotation, Letter of Offer or client letter
(Send by email, 2026-10-31), are sent by the `supplier-mail` edge function through
Resend. Until the steps below are done, Send email answers "Email is not set
up yet. Tell an admin." and nothing is sent.

## 1. Resend: the sending domain
1. In Resend, Domains, add `sc.adspace.me`.
2. Add the DNS records Resend lists (SPF, DKIM, and the return path) at the
   DNS host for adspace.me, then press Verify in Resend.
3. In the domain's settings, turn on Open tracking (Opened on the record
   reads from it).

## 2. Resend: the API key
1. API Keys, Create API key, Sending access, domain `sc.adspace.me`.
2. In Supabase, Edge Functions, Secrets, add `RESEND_API_KEY` with it.
   Never paste the key into a chat or the repository.

## 3. Resend: the webhook (delivery and opens)
1. Webhooks, Add endpoint:
   `https://hwwuigvdfubuymchsvyx.supabase.co/functions/v1/supplier-mail`
2. Events: `email.sent`, `email.delivered`, `email.opened`,
   `email.bounced`, `email.complained`.
3. Copy the signing secret (`whsec_…`) into Supabase as
   `RESEND_WEBHOOK_SECRET`.

## Senders and replies
Every email the portal sends goes from its section's sender and replies to
a company mailbox, never a colleague's own address (2026-11-17). They live
in the database (`mail_senders`, `mail_boxes`), not in secrets; the
`MAIL_*_FROM` and `MAIL_*_REPLY_TO` secrets are no longer read.

| Section | From | Replies to |
|---|---|---|
| clients (quotations, letters, New email, signing codes) | `ADspace <portal@sc.adspace.me>` | General, advertise@adspacestudios.com |
| suppliers | `ADspace <portal@sc.adspace.me>` | Accounts payable, ap@adspacestudios.com |
| creators | `ADspace <portal@sc.adspace.me>` | Accounts payable, ap@adspacestudios.com |
| careers (hiring) | `ADspace <portal@sc.adspace.me>` | General, advertise@adspacestudios.com |
| finance (invoices, overdue reminders) | `ADspace Finance <portal@sc.adspace.me>` | Finance, finance@adspacestudios.com |
| team (invitations) | `ADspace Digital Portal <portal@sc.adspace.me>` | General, advertise@adspacestudios.com |

e-Invoice, einvoice@adspacestudios.com, is kept for e-invoice submissions
alone. The four mailboxes are edited in Settings, Messages: Reply-to
mailboxes. Any address on the verified `sc.adspace.me`, `br.adspace.me` or
`rs.adspace.me` domains sends with the same API key.

The function runs with Verify JWT off: Resend calls it with no session, and
a send is checked as the colleague by the database.
