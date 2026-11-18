-- ===========================================================================
-- EVERY EMAIL FROM PORTAL@ (2026-11-18)
-- ===========================================================================
-- WHY: Resend's deliverability check, read by the user on 2026-11-18:
-- "Don't use no-reply": an address that says it takes no reply lowers the
-- inbox's trust. The user: "use portal@ then".
--
-- WHAT IT CHANGES
--   * `mail_senders`: every section sends from portal@sc.adspace.me, each
--     keeping its own name (ADspace, ADspace Finance, ADspace Digital
--     Portal) and the company mailbox it replies to; the address check
--     takes any plain address on the three sending domains, never a
--     noreply- one.
--
-- ORDER: this file (connector), then the edge functions (`_shared/mail.ts`'s
-- fallback reads portal@ too). An email sent meanwhile goes from the old
-- address, which still sends. Safe to run twice.
--
-- ROLLBACK: update the six rows back to noreply-{key}@sc.adspace.me and put
-- the check back as EVERY EMAIL IN MESSAGES states it.
-- ===========================================================================

alter table public.mail_senders drop constraint if exists mail_senders_address_check;
update public.mail_senders set address = 'portal@sc.adspace.me' where address ~ '^no-?reply';
alter table public.mail_senders add constraint mail_senders_address_check
  check (address ~ '^[a-z][a-z0-9.]*@(sc|br|rs)\.adspace\.me$' and address !~ '^no-?reply');

-- END OF EVERY EMAIL FROM PORTAL@ --------------------------------------------
