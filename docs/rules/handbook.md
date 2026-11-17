<!-- triggers: js/handbook.js -->
# Handbook (`js/handbook.js`, `?s=handbook`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- A mark at the rail's foot before Settings' (`#handbookOpen`, in More on a
  phone; 2026-11-11), never a section of the rail. The company's internal files: Employee Handbook, SOPs, Policies, Templates
  and forms, Other (`handbook_docs`, `handbook_versions`,
  `2026-10-01-handbook.sql`). Every colleague reads (`is_team()`); `team.handbook`
  alone adds, edits, versions, archives and deletes (`handbook_save`,
  `handbook_add_version`, `handbook_archive`, `handbook_delete`, each
  `allowed('admin')` and filed `handbook.*`).
- Required reading (`2026-11-11-handbook-acknowledged.sql`; the user,
  2026-11-11: read and agreed before anything else opens): an admin marks a
  file required from its ⋯ (Mark required / Mark optional,
  `handbook_required_set`, filed `handbook.edited` Required reading: Off →
  On); every active colleague but an admin and the system account opens
  each required file's current version (`handbook_opened`) and
  acknowledges it (`handbook_ack`, `not-opened` before), kept in
  `handbook_reads` (RLS on, no policy, no grant); a new version asks again.
  `handbook_due()` is read beside `me()`, and while it holds anything the
  console holds the colleague on the Handbook's onboarding (`body.hb-gate`:
  the rail's sections, its foot's marks, search, its keys, the bell and the
  tab bar away; a read of it that fails holds the gate with Unable to load
  and Try again, never opening the portal; audit 2026-11-11;
  `#hbGate`, the Handbook's bar and list hidden): Welcome to ADspace, {first
  name}, n of N acknowledged over a track, a step a file (Open, then
  Acknowledge), then Every file is acknowledged with Continue onto the
  first section held. The ⋯'s Who acknowledged lists each colleague against
  the current version (`handbook_acks`). The gate is the page's; the
  database refuses no read to a colleague with a file due, and Opened is
  the page's word that it asked for the file's link.
- A file lives in the private Supabase Storage bucket `handbook` (50 MB a
  file), never in S3 or behind the CDN, at `{doc id}/{time}-{name}`. It is
  opened only through a signed link of 60 seconds made at the press
  (`createSignedUrl`), the tab opened before the link returns; nothing
  stores an address to a file. The bucket reads at `is_team()`, writes and
  removes at admin.
- A file is never overwritten: New version adds an object and a row, and
  Versions opens every earlier one. A document may be a link (https only)
  instead of a file.
- Archive (asks) hides a file from everyone but an admin; Restore never
  asks. Delete takes the title typed back, removes the rows, then the
  files (`paths` returned by `handbook_delete`).
- A colleague who is not an admin sees no Add file, no archived file, and
  a ⋯ only where there are Versions.
