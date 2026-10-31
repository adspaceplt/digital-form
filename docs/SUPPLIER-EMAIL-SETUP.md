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

## Optional
- `MAIL_FROM` replaces `ADspace <noreply-supplier@sc.adspace.me>`.
- `MAIL_REPLY_TO` replaces `ap@adspacestudios.com`.
- `MAIL_CLIENT_FROM` replaces `ADspace <noreply-client@sc.adspace.me>`, the
  sender of a client's document. Its replies go to the colleague who sends
  it. Any address on the verified `sc.adspace.me` domain sends with the
  same API key; nothing is added in Resend.
- `MAIL_CLIENT_REPLY_TO` replaces `marketing@adspacestudios.com`, where a
  client's document goes to when the colleague who sends has no email.

The function runs with Verify JWT off: Resend calls it with no session, and
a send is checked as the colleague by the database.
