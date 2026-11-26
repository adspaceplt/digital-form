<!-- triggers: supabase/ workers/ -->
# Release: applying a migration and deploying an edge function (CLAUDE.md §3)

Moved whole from `CLAUDE.md` §3 Git and delivery, which keeps a one-line pointer here; read whole before applying a migration or deploying an edge function.

- A migration is applied by Claude through the Supabase connector (project
  `hwwuigvdfubuymchsvyx`, the user, 2026-09-28), or through the Management
  API (`api.supabase.com/v1/projects/{ref}/database/query`, the token never
  printed) in a session whose connector belongs to another organisation
  (2026-11-20); never a connector on another organisation, in the order the release
  states (commonly after the Pages deploy, so the page stops asking before
  the database stops answering), and verified on the live database
  afterwards. The report names what was applied.
  - A statement holding `drop` or `delete` (a function body included) is
    run through the connector like any other (the user, 2026-11-26: "Run
    all sql dont care if its drop delete or what"), in small `execute_sql`
    pieces where one would time out, and verified live; it is never left
    for the SQL Editor. A storage policy goes in a run of its
    own, since the editor may not alter `storage.objects` and a failure rolls
    back the whole run.
- An edge function (`sign-upload`, `sign-download`, `media-pass`, `invite-member`,
  `portal-login`, `meet-create`, `push-send`, `s3-sweep`, `report-draft`,
  `meta-import`, `caption-draft`, `script-draft`, `wa-send`, `wa-hook`, `brand-analysis`, `quote-request`, `checklist-draft`, `supplier-mail`, `bukku-sync`, `analytics-read`, `creator-mail`, `portal-agent`, `hiring-mail`, `outstation-geo`) is
  deployed by Claude through the
  Supabase connector from the repo copy, keeping its Verify JWT setting, and
  the live source is read back (the user, 2026-09-30) and compared with the
  repo file before anything else; a file is always sent whole, never in
  part (2026-10-16: a half file broke `report-draft` for three minutes),
  its content pasted in the call itself, never a placeholder to fill later
  (2026-10-19: `meet-create` served a placeholder for 50 seconds).
  Before a deploy, `main` is fetched and merged into the branch, and the
  live version compared with `main`'s file: sessions run at once, and a
  deploy from a branch behind `main` takes away what another session
  deployed (2026-10-29: `bukku-sync` v12 removed #814's button for five
  minutes).
  The connector turns a `\u` escape into its character, so a function file
  writes such characters as themselves, keeping the read-back byte for byte.
  A function that imports `../_shared/` is sent with that file in the same
  call (`wa-send`, `supplier-mail`: `_shared/pdfref.ts`; `supplier-mail`,
  `bukku-sync`: `_shared/mail.ts`, the one email layout and Resend send; every function a
  browser calls: `_shared/cors.ts`, the one list of origins and the one
  answer's headers, `tests/mailfn.js`), and both read back.
