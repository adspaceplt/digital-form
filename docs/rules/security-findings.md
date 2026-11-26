<!-- triggers: supabase/ client/ admin/index.html js/passkey.js js/portal.js workers/ js/trace.js -->
# Security findings: what each audit found and closed (STANDARD.md §24)

Moved whole from `STANDARD.md` §24 Open security findings, which keeps the open items and a one-line pointer here; read before a security audit or a change to sign-in, policies or functions.

- The audit of 2026-11-07 (run 1, 0a858d0) and its scoped second run of
  2026-11-09 (5bd5452, the seven areas run 1 left): every confirmed finding
  of both closed the day it was found (`docs/DECISIONS.md`). Closed
  2026-11-21: `private/` trusts only its own key group
  (`adspace-portal-private`, `cf_private_files_key_id`); checked live, a
  media pass is refused there, by its own path and by a dot-segment one. The eight AI functions' `npm:@anthropic-ai/sdk` import is
  pinned to 1.10.0 and deployed (2026-11-21); `tests/fnpins.js` fails any
  `npm:`, `jsr:` or esm.sh import without an exact version. A creator's signed uploads are counted a
  booking a day since 2026-11-09; an AWS Budgets alarm is set (the owner,
  2026-11-21); the S3 lifecycle rule's storage-class half stays held. The client portal's sign-in, hunted
  2026-11-24 (`portal-login`, `portal_clients`, `get_portal`,
  `portal_work`, `portal_link_pass`, the stamp, sign-out, media-pass and
  sign-download for a contact, every function `authenticated` may run):
  nothing a client can reach crosses to another client; checked live,
  sign-ups are off and Auth's captcha refuses an emailed sign-in without
  a token. A Past client's contacts, and an inactive client's, are
  refused by every portal function, media-pass and portal-login as a
  stranger is, unless the team keeps the client's access on from its
  record (finding 3, closed 2026-11-24, `portal_client_open`,
  `tests/portalpastsql.js`). Left with the owner: GoTrue answers an unknown
  address differently from a known one (captcha per probe), and the email
  code's length and expiry are dashboard settings.
- None open from the audit of 2026-10-16's five must-fix findings: 1
  (`delete_client` refused no one), 2 (a creator's file address drawn
  unescaped in the console), 3 (a post link holding a quote) and 4
  (`sign-upload` signing any extension, type and size for a day) closed
  and live on 2026-10-17; 5 (three internal helpers open) was already
  closed by `2026-09-27-internal-helpers-stay-internal.sql`.
- The same audit's second batch (A to N) closed and live on 2026-10-17:
  Malaysia's day in every function (A), a team send-back holding against
  the client's link (B), a WhatsApp send never repeated by itself (C), the
  review settings held to their columns (D), admin made only by an admin
  (E), a quoted letter priced as quoted (F), every AI run that reached the
  model counted (G), the legacy bucket unlisted (H), the backup's CLI
  pinned (I), the CDN scripts pinned by hash (J), the portal's unused
  weight shed (K), creator codes from a strong source (L), every stored
  link held to the web (M) and three guard suites (N). Declined by the
  user: 6, 15, most of 20, and any change to the root pages. The three
  helpers restated with a grant after INTERNAL HELPERS STAY INTERNAL
  (`ops_due_decider`, `option_qc_count`, `ops_owner_may_move`) closed again
  on 2026-10-18 (`2026-10-18-internal-helpers-closed-again.sql`);
  `tests/sql.js` holds every helper's last word in the schema a revoke.
- The audit of 2026-10-10 closed in five batches (the last, F3:
  a media pass per client folder). Checked live on 2026-09-27: every public table has row level
  security on, no policy reads `true`, and every policy asks `allowed()`,
  which answers false for anybody who is not an active colleague. The
  internal helpers the API could still reach are closed
  (`2026-09-27-internal-helpers-stay-internal.sql`). A client's billing
  columns, readable by every section that reads clients, are withheld from
  the table and answered by the Billing part (2026-09-28,
  `2026-09-28-client-billing-columns.sql`).
