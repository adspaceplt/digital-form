-- ===========================================================================
-- WHATSAPP SHORT LINK (2026-11-22, the user: "How bout use new short link
-- hi.adspace.me/whatsapp", "Redirects to wa.me/adspace"). 2026-11-22. Safe to
-- run twice. Rollback at the foot. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/hiringsql.js compares the
-- two.
--
-- WHAT CHANGED
--   * Short Links holds `whatsapp` (hi.adspace.me/whatsapp → wa.me/adspace),
--     made only where no link holds the slug; the team edits or pauses it in
--     Short Links like any other.
--   * Interview time changed and Interview confirmed give that link in their
--     way to reschedule, in place of wa.me/adspace, so every link a
--     candidate email carries is on the sending domain again (CLAUDE.md,
--     Emails). Only the link moves; any other words the team set stay.
--
-- ORDER: this file alone (Management API). hiring-mail fills no link of its
-- own, so it is not redeployed.
--
-- ROLLBACK
--   update public.hiring_email_templates set body = replace(body,
--   'WhatsApp: https://hi.adspace.me/whatsapp', 'WhatsApp: https://wa.me/adspace')
--   where kind in ('confirm', 'rescheduled'); the link may stay.
-- ===========================================================================

insert into public.links (slug, target_url, title)
select 'whatsapp', 'https://wa.me/adspace', 'WhatsApp'
 where not exists (select 1 from public.links l where l.slug = 'whatsapp');

update public.hiring_email_templates
   set body = replace(body, 'WhatsApp: https://wa.me/adspace', 'WhatsApp: https://hi.adspace.me/whatsapp')
 where kind in ('confirm', 'rescheduled') and position('WhatsApp: https://wa.me/adspace' in body) > 0;

-- END OF WHATSAPP SHORT LINK --------------------------------------------------

select public.functions_tidy();
