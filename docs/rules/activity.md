<!-- triggers: js/records.js -->
# Activity record

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- Every tag written is named in `ACTION_LABEL` (`js/admin.js`).
  `activity_section()` in SQL restates the map, and `tests/sql.js` §21 compares
  the two. A new tag is written into its first copy in `schema.sql` as well as
  the release's restatement: `sql` and `ops` hold the two the same.
- A tag nothing names files as `other` and falls back to the section.
- One part per section (`activity.clients`, `.whatsapp`, `.ops`, `.team`,
  `.review`, `.scripts`, `.campaigns`, `.links`, `.register`, `.reports`,
  `.services`, `.handbook`, `.hr`). The link draws where any part is readable.
- An HR letter's history (a Documents tag filed under subject HR) is its own
  part, HR letters (`activity.hr`), after Documents in the Section select:
  `activity_read` answers it only at `activity.hr` and `register.hr` View
  together, and Documents reads without it (`2026-10-24-hr-history-apart.sql`,
  S5; the user: "file it apart").
- Reports files a report's steps (`report.*`: started, submitted, returned,
  confirmed, published, revised, unpublished, deleted), every save
  (`report.saved`, filed by the page through `fileReport()`: the period and
  version, then the step or sheet and what it held) and every Draft with AI
  (`report.ai_drafted` with its language, `report.ai_failed` with the
  reason) (`2026-10-01-activity-reports-tab.sql`).
- Performance follows Team (`team.performance` View, no master code), read
  through `perf_activity()`: when, the step, whose month, who; never a score,
  a grade, a breach or a dispute's words, and never the caller's own review.
- The sections are one Section select (`#activitySection`, its label at its
  left; 2026-10-11, in place of a strip of fourteen tabs): All sections
  first (never Everything), then only the sections whose part the reader
  holds (Performance at `team.performance`), in the rail's order, opened on
  the section the record was opened from where it is offered, else All
  sections; ten or more open the finder. The sheet holds no swipe region.
- A client's lines carry its id (`activity_log.client_id`): the console
  names the client it acts on (`ADspaceAdmin.log(action, client, …)`, the
  record as subject), a function's line takes the client its transaction
  wrote (`activity_log_client`, `activity_client_note`; an id, never a
  name), and the client's Activity and rail read by it. A campaign's and a
  creator's lines carry theirs the same way (`activity_log.campaign_id`,
  `creator_id`: the console's `{ name, campaign }` / `{ name, creator }`, a
  function's `campaign.*` / `creator.*` line from `activity_campaign_note`,
  `activity_creator_note` and `activity_log_ids`), and their panes read by it.
- The Activity record reads its chosen section alone (`.in('action', actionsOf(k))`), newest first, 200 a page, Show older reading the next; a failed read is `failLine` with Try again (ACT-1, ACT-2, 2026-10-22).
- Every history (the Activity record, a client's and a campaign's Activity and
  rail, a task's log and recent activity, and every Performance history) is
  drawn by `js/records.js`
  (`ADspaceRecords.paint`): at 720px and over one 12.5px line an entry
  (`.reclist.is-wide`: time, what and on what, the detail cut at the line's
  end in the soft ink, who at the right edge in a 150px track, a hairline
  between entries); narrower, two lines (time, who in mute ink, what and on
  what; the detail under it), each cut at its end; a cut entry opens on a
  press. A heading a day, and a run of the same act by one
  person on one thing within ten minutes folded into one entry (`×n`). On a
  campaign's own page a booking's entry is about its creator (`lead`, the
  detail's first part), and `detailOf()` drops words the first row says
  (`quality checked by …`, `schedule updated`). Sticky entries never fold: Performance, HR, voids, deletes,
  removals, billing, rates, invoices, access and groups, a client's decision
  on a draft and a creator's hand-in (`stickyOf`).
  `ADspaceAdmin.record(row)` is the one reading of an `activity_log` row.
  A run folds only on the same thing: its `key` (a document's subject and
  reference; a booking's campaign and the creator its detail names first,
  written once on the folded line; the record a pane belongs to) else its
  subject; with neither,
  only identical lines fold. A field changed twice reads as its path
  (`Admin → Team → Admin`), a run reads `· 3 times`, and a cut entry is a
  button with `aria-expanded` (`is-long`).
  `register.added` / `register.edited` read Document added / edited.
- A line a page files in the Activity record names the address the caller
  signed in with and the moment it arrived, whatever the page sent (trigger
  `activity_log_stamp`, `2026-11-07-activity-actor-stamped.sql`); a
  function's own line keeps its actor.
- Every save files what it changed, from and to (`ADspaceRecords.changes`:
  "Label: old → new", empty reads "not set"); a save that changed nothing
  files nothing. Client details, brand, contacts, rate lines, team members,
  groups and access (`accessMoves`) name values. Billing names the fields
  only (`{ names: true }`), never their values. A Documents edit is filed by
  `register_update` itself (the serial, then each move; `register_day` writes
  `12 Sept 2026`); an HR row is filed under `HR` with its type, date, note
  and file only.
- `document.*` and `register.*` rows file under Documents.
- A prospect's or client's step on a quotation link is its own line under
  Clients (`quotation.requested`, `.opened`, `.changes`, `.withdrawn`,
  `.declined`, `.signed`), subject the client's name, filed by
  `quote_activity` with its facts in `activity_log.meta` (reference, who,
  device and browser, city and country, session reference); an entry with
  facts never folds and opens to them as `dl.ovfacts.rl-facts`. A caller's
  address is never among them (`activity_log_meta_check`), and only a
  function writes them (`activity_log_stamp` clears a page's)
  (`2026-11-25-quotation-link-activity.sql`, `tests/quotelinksql.js`).
- The record keeps three years: `privacy_retention()` (pg_cron
  `privacy-retention`, daily at 02:45 MYT since 2026-11-26) removes older rows, and
  clears a WhatsApp message's number, name, variables and link code twelve
  months after it was queued, never one still queued or sending
  (`2026-10-18-personal-data-kept-for-a-time.sql`), and removes a caller's
  address against a link's passcode (`link_tries`) once its last try and
  last opening are 30 days old and no lock stands
  (`2026-10-18-passcode-tries-kept-for-a-time.sql`).
