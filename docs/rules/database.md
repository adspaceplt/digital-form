<!-- triggers: supabase/ -->
# Database rules

Moved from `CLAUDE.md` §2, Writes, refusals, reversibility, on 2026-11-23: the lines only SQL meets. The page-side lines stay loaded.

- A column added to a table a page reads through column grants
  (`clients`, `team_members`, `quotations`) is granted in the same file
  (2026-11-06: `quotations.sent_out_at` without its grant refused the
  whole Quotations list; `tests/sql.js` reads the list's columns against
  the schema's grants).
- A security definer function replaced keeps every refusal of the one
  before it (2026-10-17: `delete_client` lost its own and refused no one).
- A guard trigger holds an insert as it holds an update, a page's insert
  read against a blank row (2026-10-22, SEC-1: a client could be inserted
  Active with billing by a colleague without the Billing part).
- A public form's typed name is never an actor: it is filed under the form
  (Details form, Supplier form, Quotation portal), the name in the detail
  (2026-10-22, BE-3).
- What a client page or a creator writes through a function is held to a
  length: a name 80, a note 2,000, a caption 5,000, refused `too-long`
  before anything is written (`submit_review` `too_long`; `review_draft`,
  `confirm_selection_with`, `creator_submit`,
  `portal_request_once`; `2026-10-18-what-a-client-types-is-held-to-a-length.sql`).
- A template is saved only with the fields its sender fills
  (`2026-11-10-template-fields-checked.sql`; the overnight review,
  2026-11-10): every template save (supplier, client, Email templates, both
  invoice emails, creator emails, the Meeting message) asks
  `template_check(text, kind)` against `template_fields(kind)`, the one list
  of each sender's fields, refusing `unknown-field` with the field and the
  list, said as `ADspaceWords.line.unknownField` (Unknown field {x}. Use …);
  `template_fields_all()` answers the lists to the team (`tests/tplfieldsql.js`).
- A colleague is found by their id (`clients.owner_id`, `campaigns.owner_id`,
  `quotations.made_by_id`, `submitted_by_id`, `activity_log.actor_id`,
  `member_id`), never by the name a record holds: the name is a snapshot,
  written from the id where a page picks a colleague (`owner_id_stamp`), else
  stamped from the caller's own; a name written alone links only the one
  colleague holding it; backfilled only where one colleague holds the name
  (2026-11-28, `colleagueidsql`, `owneridsql`). Every "by whom" name column
  keeps its `{column}_id` beside it, stamped by `whom_ids` (the trigger's
  arguments are its pairs) from the caller alone; a new one joins its
  table's trigger in the same push, and a page shows it through
  `ADspaceAdmin.whoIs(id, name)` (`whomidsql`).
- A uuid column naming one record holds a foreign key stating its `on delete`:
  cascade only where the row cannot stand without its parent, set null where
  the history must survive, restrict where the delete is refused; added `not
  valid`, validated where no row points at nothing (2026-11-28, release 4;
  `idguard` counts the columns without one). A polymorphic id, a uuid array
  and an id a recorded decision keeps past its parent hold none.
- A value that depends on a change is stamped by a trigger, never by a page. A
  trigger never forces a column back to its old value.
- Two releases restating one function merge in turn: the later one's
  restatement holds the other's change and its band follows the other's in
  `schema.sql` (2026-11-06: #925 restated `app_settings_set` without
  #924's `report_post_links`).
- PL/pgSQL: declared names never match a column, and lookups are qualified. A
  shadowed name fails at run time, not at create time. A `for a, b in select …`
  loop's targets are scalars alone: a row variable among them fails at run
  time, never at create time (2026-11-12, `review_revert_confirm`, caught
  live before it was applied).
- A function's today, and a column's default day, is Malaysia's, `(now() at time zone 'Asia/Kuala_Lumpur')::date`,
  never `current_date` or `now()::date` (`tests/sql.js` reads every
  column's default; 2026-10-22, BE-9) (the database runs on UTC: yesterday
  until 8am; 2026-10-17, `tests/sql.js` reads every function's last
  definition). The database's TimeZone stays UTC: PostgREST writes timestamps
  in it and the pages read them so. Months are taken off Malaysia's local
  time before it is made a moment (`(date_trunc('month', now() at time zone
  'Asia/Kuala_Lumpur') - interval '3 months') at time zone 'Asia/Kuala_Lumpur'`):
  `at time zone` binds before `-`, so the other order counts on UTC's
  calendar (2026-10-17, `portal_meetings`).
- A day a function writes in words is `register_day` of its Malaysian day
  (`5 Sept 2026`), never `to_char(…, 'Mon')` (`Sep`, and the UTC day;
  2026-10-19, a moved date's notice).
- PostgREST cannot choose between overloads a call fits, so a changed signature
  drops the old one first.
- An embed across two foreign keys names the key
  (`team_members!ops_task_assignees_team_member_id_fkey(name)`). A refused read
  of who owns what fails the list; it never draws an unowned row.
- A check a later band widens (`wa_templates_purpose_check`) is added `not
  valid` in every earlier band, so the schema runs again over rows the later
  band allows (2026-11-11: `representative` made the re-run fail three times).
- A save of several rows checks every row before it writes any: a function
  returning a refusal commits what it wrote before it, so a loop never both
  writes and refuses (2026-11-24: candidate and creator emails, Reply-to
  mailboxes, a performance query and scripts published stood half saved;
  `tests/wholesql.js` reads every function's last definition).
- A new band joins `schema.sql` after its last line, its own `select public.functions_tidy();` after it, never inside the band before it: a suite holds each migration's whole text in the schema (2026-11-27: the quotation holds band split the made-by-id band's ending).
- A seed is a first run, not a running list.
  - Catalogue rows (the rate card, `detail`, Marketing and Sales) seed only
    into an empty table.
  - Admin alone is ensured on every run.
  - `on conflict do nothing` does not protect a deleted row.
- A record whose rows are written only by security-definer functions takes
  no direct write policy (`with check (false)`): `reviews`,
  `option_reviews` and `creator_profiles` as `campaign_confirmations`
  (security audit 2026-11-09: a colleague at Work filed approvals as the
  client's and stored any profile link); a post's `round` moves only by
  the database (`posts_round_guard`, run as the caller).
- A trigger that calls a function closed to `authenticated` is security
  definer itself (2026-11-09: the creator and campaign ID triggers called
  `id_take` as the colleague, so adding either failed).
- Every `ops_`/`perf_` write goes through a security-definer function. The
  tables carry a select policy only, or no policy at all (`perf_`).
- Supabase grants EXECUTE on every new function to `anon` and
  `authenticated`. A helper no page calls (only other functions do) revokes
  itself from `public, anon, authenticated` in the file that creates it;
  one used by a policy, a view, a default or an invoker function keeps
  `authenticated`. A helper restated later keeps its revoke, never the
  grant of its first definition (2026-10-18: three were reopened so;
  `tests/sql.js` reads each helper's last word in the schema).
- No table or view in public grants anon anything (`2026-11-15-database-safeguards.sql`,
  revoked on every pass, Supabase's default grants included; phase 2 audit
  19): a signed-out page reads through functions alone, and a table made
  later is revoked by the band's next run (`tests/sql.js`).
- Function hygiene (`2026-10-07-function-hygiene.sql`, `functions_tidy()`,
  the owner's alone): every function in public names its search path
  (`public`), and anon runs a security definer function only where a public
  page calls it: `open_to_anon`, exactly the functions `schema.sql` grants
  to anon (`tests/sql.js` holds the two equal). It revokes from `public,
  anon` and gives `authenticated` and `service_role` back what they had.
  `schema.sql` ends with `select public.functions_tidy();`, and so does every
  migration that adds or replaces a function. A new function a public page
  calls is granted to anon and joins `open_to_anon` in the same push.
  The hygiene file runs before that function's migration: the migration's
  own closing `functions_tidy()` closes to anon whatever the list does not
  yet name (2026-11-27, `link_hit`, re-granted live).
- A catalogue change (for example a rate card revision) ships as a migration
  guarded line by line on the seed's value. It comes with a `-preview.sql` that
  reads and writes nothing and reports per line `will change`, `already`, or
  `edited in the console, left alone`.
- A business figure the team may change (an amount, a threshold, a rate, a
  limit) is a setting an admin edits, effective from a date or period, read
  by the function that applies it; never a number typed into code (the user,
  2026-10-05: "what if i need changes the next quarter"). Outside
  Performance they are `app_settings` (`2026-10-05-app-settings.sql`, key,
  from_date, value; RLS on, no policy, no grant): `app_setting(key, at)` for
  functions, `app_settings_read()` for pages (anyone the team does not hold
  is answered `sst_pct`, the term percentages, `fx_sgd`, `ad_prepay_pct` and `ad_credit_fee_pct` alone, what a client page
  prices with or prints (`2026-11-27-ad-spend-figures.sql`); `2026-10-19-settings-a-client-page-reads.sql`), `app_settings_set(p_from,
  p_values)` an admin's, from today (MYT) or later (`past`); a figure is the
  one in force on the day, the first row standing in for an earlier day
  only where the schema seeded it (`app_setting`, `setting()`; a figure
  planned for a later day is unset before it; 2026-10-22, BE-5), filed
  `team.changed` under Settings; a value saved for a planned day that equals
  the one in force the day before withdraws that day's row, filed "planned
  change withdrawn" (`2026-10-19-planned-setting-withdrawn.sql`). An edge
  function reads a setting in force from `app_settings_read` through one
  helper (`settingsAt`; `app_setting` is closed to a caller). One sheet edits a group of them
  (`ADspaceAdmin.editSettings`, open until the database answers, a refusal
  said in it with every figure kept (2026-11-10): From, then each figure, under its
  section's heading where a key names one, a change already set from a
  later day said under its field with its unit as the Settings row says it
  and Withdraw on it; each untouched figure shows the value in force on the
  From day, and only a figure differing from it is sent, so one typed back
  to the figure before a planned change withdraws it (2026-10-20, SET-1)):
  Follow-up limits, Tax and terms (`ADspaceAdmin.TAX_KEYS`, eight figures
  in three sections), Due dates (report and revision days, past dates on new tasks), each the
  Settings page's alone (2026-10-29), `team.settings`. Every sheet is
  `ADspaceAdmin.SETTING_SHEETS`, read by the Settings rows and every other
  door alike, so it asks and says the same from each (2026-10-22, SET2-4);
  it opens on its first figure at a desk and on its card under a finger
  (`ADspaceConfirm.ask` `focus`, SET2-6), and AI prices has its Settings
  row alone, never a button in AI usage (SET2-5).
- Row level security is stated one `alter table … enable row level security`
  line per table, never in a `do $$` loop.
- A trigger that stamps a column's change fires `before update` and compares
  old with new itself, never `update of {column}`: another trigger may set
  the column (`team_access_guard` sets `active`), and a stamp is set afresh,
  never kept with `coalesce` (`team_members_inactive_stamp`).
