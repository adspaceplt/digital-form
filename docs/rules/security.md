<!-- triggers: supabase/functions/ client/ admin/index.html js/passkey.js js/portal.js workers/ js/trace.js -->
# Sign-in, security, secrets

Moved from `CLAUDE.md` §2, Sign-in, security, secrets, on 2026-11-23. Secrets and the rule that nothing deletes from S3 stay loaded in `CLAUDE.md`.

- Send invitation always sends one (2026-11-11, the user: two went
  nowhere): Supabase invites only an address with no login, so for one that
  has a login `invite-member` sends the same invitation itself through
  `_shared/mail.ts` (from the team's sender, a one-time sign-in
  link from `generateLink`, a key of its own each send), and a page says
  Invitation sent only on `sent`, never on `already`. A colleague is
  greeted by the name on their record, an admin alone wording it otherwise
  (audit 2026-11-11).
- An active colleague's first sign-in makes their login (2026-11-11, the
  user: one added with no invitation read Active and was sent no code): the
  console asks `portal-login` before the code, which makes a login for a
  live portal contact or an active colleague not removed or erased, and for
  nobody else, answering alike either way.
- A sign-in email's button opens the portal's own page, never supabase.co
  (2026-11-18, Resend's check: a link off the sending domain reads as
  spam): `?token_hash=…&type=email` (an invitation `invite`) on the page
  asked from, proved by `js/api.js` before any read of the session, the two
  words taken out of the address; the dashboard's templates
  (`docs/SIGN-IN-EMAILS.md`) and invite-member's own invitation
  (`hashed_token`) alike (`tests/signin.js`, `tests/invitefn.js`).
- `/admin/` signs in with the emailed link or the code (`#authCode`, 6 to 10
  digits, `verifyOtp` type `email`), or with a passkey (supabase-js 2.117.2 on
  `/admin/` only).
  - Passkeys are managed in the account menu.
  - The passkey offer shows once per browser (`adspace-passkey-offer`).
  - A passkey that proves the person already signed in goes through
    `ADspacePasskey.prove()`, never a bare `signInWithPasskey` (which signs
    in whichever account's passkey the browser offers). It is offered only
    to a person with a passkey of their own (`mine()`); the console holds its
    auth events meanwhile (`ADspaceAdmin.hold`); another account's answer is
    revoked on this device (`signOut({ scope: 'local' })`) and the person's
    own session put back (`setSession`), else the console signs out.
- The demo (`js/demo.js`, `demo/`): `docs/rules/demo.md`.
- Overseas access (`team_abroad`, `team_place_ok`): `docs/rules/overseas.md`.
- One person per console: a session that turns into somebody else's (another
  tab, any sign-in over this one) restarts the console from the top
  (`gate()`, after 1.5s unless the session has come back).
- `/client/`:
  - Asks `portal-login` first. It makes a login only for a live contact with
    `portal_access` at a client whose portal is open (`portal_login_name`,
    never a Past client's unless kept on; 2026-11-24), and answers `{ok: true}` to every address, each in the
    same least time (`FLOOR_MS`, 1,500 ms, a slower run at the next whole
    step; a fault logged, never a 500), so
    the wait never says who is a client (2026-10-25, `tests/portalloginfn.js`).
  - `signInWithOtp` with `shouldCreateUser: false`.
  - The email's code signs in on the page as well as its link (`#signCode`,
    6 to 10 digits, `verifyOtp` type `email`), with Use another email; a wrong
    code reads the same for every address.
  - Reads only through `get_portal`, `portal_request` and `portal_withdraw`.
  - A company select appears where one address holds access at several
    clients.
- Sign-in never says whether an address has an account ("If {email} is
  registered, …").
- An edge function reads a caller's address as `cf-connecting-ip`, else the
  last X-Forwarded-For entry, never the first (`media-pass`, `sign-download`,
  `quote-request`; 2026-10-25), and asks every function that counts a
  caller (one reading `request_ip()`, directly or through another, as
  `creator_code_try` does) on a client carrying it as `x-adspace-ip` beside
  the relay secret, never the bare service role, whose address every caller
  shares (`sign-upload`'s creator calls, 2026-11-24; `tests/iprelay.js`).
- Every call an edge function makes outside Supabase carries a time limit
  (`AbortSignal.timeout`: 15 seconds, 20 for S3 and Meta's Graph; a file
  streamed from S3 is held only until S3 answers), and its catch names the
  failure; every Claude call is `maxRetries: 0` with a timeout of what is
  left of the function's budget (`max(5000, budget - elapsed)`), never a
  fresh limit per call (the review of 2026-11-25).
- An email is matched as itself in every edge function (`exactEmail`: `_`
  and `%` are letters, never wildcards; audit P2, 2026-10-10).
- A colleague's upload names its purpose and record, and `sign-upload`
  signs it only for that (audit P1, 2026-10-10): `review` a content set
  (`batchId`, Content Review: Sets at Work), `logo` the client (Clients or
  Content Review: Client settings at Work), `campaign` a booking whose draft
  is owed (`optionId`, Creators: Campaigns at Work), `invoice` a
  campaign (`campaignId`, Creators: Finance at Work, private where
  set up), `report` a report version (`versionId`, Reports at Work, always
  private, its scope asked of the report's client), `thumb` a report's
  picture (`reportId`, Reports at Work, always private, a JPEG under
  `private/{client}/thumbs/`); the record must be the named client's and the caller's client
  scope must reach it, each asked as the caller. Work in one section signs
  nothing for another; a page that names no purpose is asked to reload.
- `sign-upload` signs only the extensions the pages upload (`EXT_TYPE`:
  video, picture, PDF, ZIP; never HTML, SVG or script; `bad_extension`),
  each with its one type, and signs that type and the size claimed into
  the PUT for fifteen minutes (`X-Amz-Expires` 900); every page PUTs with
  the `contentType` it answers (2026-10-17, audit finding 4). Every picker
  that feeds it offers only those extensions (`ADspaceAPI.uploadAccept`),
  and its refusal, a non-2xx that supabase-js leaves on `r.error.context`,
  is read by `ADspaceAPI.fnRefusal` and said in words (`W.uploadType`),
  never "non-2xx".
- A client's review link and a campaign's selection link carry an
  eight-character key (`?k=`, alphabet `23456789abcdefghjkmnpqrstuvwxyz`),
  made by `ADspaceAPI.accessToken()` in the console and `new_link_key()` in
  SQL (`2026-10-01-short-links.sql`), never `Math.random`. A long key from
  before is kept as `moved_token`: it opens nothing itself, and
  `link_moved(kind, token)` answers it with the current key, which the page
  puts in the address and loads. Changing a key (Reset link) clears
  the moved key by trigger, so a reset retires every earlier link. A
  campaign's is reset from its ⋯ (`campaign_reset_link`, Creator
  Campaigns: Campaigns at Work, a key from `new_link_key()`), and
  `get_campaign` answers `not-found` once the client is Past (2026-10-18),
  so `sign-download` and `media-pass` close with it, as do
  `save_selection`, `confirm_selection_with` and
  `review_draft`, before the passcode, and `share_link_preview` names no
  Past client (`2026-10-18-past-client-links-act-on-nothing.sql`); a
  completed campaign stays readable for its results, a Past client's too,
  read only (`selection_closed`, no backups; every write above still
  refuses; `2026-10-18-completed-campaigns-stay-readable.sql`, the user:
  988's results were never read).
  A link's passcode is asked through `link_passcode(kind, token, stored,
  given)` by `get_review_feed`, `submit_review`, `submit_review_seen`,
  `get_campaign`, `save_selection`,
  `confirm_selection_with` and `review_draft`
  (`2026-10-18-passcode-locks-per-caller.sql`,
  `2026-10-18-review-decisions-ask-the-passcode.sql`): asked without one is never
  counted; wrong ones are counted per link and caller address
  (`link_tries`, `request_ip()`: the address Cloudflare saw,
  `cf-connecting-ip`, else the last X-Forwarded-For entry, never the first,
  which the caller writes, an IPv6 address read as its /64
  (`2026-10-29-review-fixes.sql`); `media-pass`, `sign-download` and the
  links Worker (its `IP_RELAY_SECRET`, a creator's preview) pass their
  caller's on as `x-adspace-ip` beside `x-adspace-relay`, the
  `ip_relay_secret` in `app_secrets`, the only way it is taken;
  `2026-10-18-a-callers-address-is-cloudflares.sql`; both rows taken under
  a row lock before any passcode is compared, so guesses sent at once are
  counted in turn, `2026-11-07-passcode-tries-counted-first.sql`), five within
  15 minutes locking that address out, the right one included, for 15
  minutes, then an hour, then a day where it is locked again within a day
  of the last lock ending (`strikes`, `struck_until`; the right code and
  Clear start the steps again; `2026-10-18-passcode-locks-lengthen.sql`);
  a new or changed access code is six characters at least (trigger
  `passcode_long_enough`, `passcode-short`; Access code says so before
  it saves), one set before keeping its place; the link's own count (`link_attempts`, 100 within an hour)
  locks it for an hour for every address but one that opened it in the
  last 30 days; each answered `locked` with its minutes (`link_locked`),
  said on the page as Link temporarily locked (`W.lockedLine`), and a
  stored code that no longer opens the review link is let go, the media
  pass not asked again. The team reads a lock under the link
  (`link_lock_state`, `.linklock`) and clears it (`link_lock_clear`, the
  section at Work, filed). A passcode asked for names nobody; the tables
  have RLS on, no policy, no grant.
- Where a colleague copied a quotation's link (`quotation_link_copies`,
  `request_ip()`, never a header a caller sets; QUOTATION COPIER'S
  OPENING, 2026-11-25) is kept for one purpose, telling the team's own
  opening from the client's, and cleared 30 days after the copy by the
  monthly `privacy_retention` (PDPA 2010). RLS on, no policy, no grant;
  never answered to a page or drawn on a screen.
- S3 (`docs/S3-STORAGE.md`): the upload key only writes under `content/`,
  and under `private/` (write and read, for invoices, each published
  report's kept PDF and every report picture, `private/{client}/thumbs/`,
  read through S3 links sign-download signs, the bucket's CORS allowing
  GET and PUT from the portal; S3-STORAGE §7) once §5 is done;
  `private/` reaches CloudFront only through its own `private/*` behaviour,
  each link signed by `sign-download` for one file with `private/`'s own
  key (`cf_private_files_private`, `cf_private_files_key_id`, key group
  `adspace-portal-private`), never the media pass's (2026-11-21). `content/` is
  served only with the media pass (§6 done; CloudFront's `content/*`
  behaviour requires it since 2026-10-09) (`media-pass` signs with a
  key it made and keeps in `app_secrets`, `cf_media_private`; CloudFront's
  ID for it is `cf_media_key_id`, and until it is stored the function
  answers `{ off: true }`).
  Nothing deletes from S3 (loaded in `CLAUDE.md`). `s3-sweep` is a daily report only (pg_cron,
  03:17 MYT, `s3-sweep-daily`): with a list-only key it lists `content/`,
  asks `s3_keys_in_use()` (service role only; each column read once a run,
  `2026-10-18-s3-keys-read-once.sql`) which files a row still names,
  judges only objects over 7 days old, and files the counts in `s3_sweeps`.
  Its code has no delete request, and `tests/s3sweep.js` holds that. A
  video's `.web.mp4` copy counts as in use while its original is.
- Scheduled jobs are watched (`2026-10-18-scheduled-jobs-watched.sql`):
  `jobs_watch()` (pg_cron `jobs-watch`, 08:20 MYT) tells each active admin
  (none active: Team Full Access) once a day (kind `jobs.failed`) of the
  scheduled runs that failed since its own last successful run (24 hours
  to seven days, a failed check of its own named first), by job, of an S3
  report filed as failed or not arrived in 26 hours, of a nightly Bukku read
  that failed or wrote no beat in 26 hours (`job_beats`, RLS on, no policy,
  no grant), of creator emails failed or not confirmed, and of each repeat rule
  that could not make its task, named (client, rule or task, its number;
  five, then a count), the notice opening the first one's task; the morning
  run keeps a rule nobody active can make, or whose task its colleague
  cannot see, as its error, which the task card's Repeats line shows
  (`2026-10-18-failed-jobs-named.sql`), and of the automatic WhatsApp
  messages that failed in the window, counted (`2026-10-26-jobs-watch-whatsapp.sql`); `jobs_prune()` (`jobs-prune`, 03:40 MYT) removes job history
  over 14 days and notices read over 90 days ago or unread over 180
  (`2026-10-19-unread-notices-pruned.sql`), never a colleague's notice. Neither is a page's to call.
- The database is kept every night (`workers/db-backup/`,
  `.github/workflows/db-backup.yml`, 02:37 MYT; the user, 2026-10-10: the
  Free plan keeps no backups): Supabase's own dump (roles, schema, data),
  refused when it holds no client row (an empty clients table too; its
  workflow's actions pinned to commits, 2026-10-22, SEC-2, BE-10),
  encrypted with `BACKUP_PASSPHRASE`, put
  at `private/backups/db/db-{MYT day}.tar.gz.gpg` by a key that may only add
  there; it runs on its schedule or by hand, never on a pull request, and
  reads, lists and deletes nothing (`tests/dbbackup.js`). Storage objects
  (the Handbook) are not in it.
- Video conversion (`workers/video-convert/`, AWS Lambda `adspace-video-convert`
  on the bucket's ObjectCreated under `content/`, the user's own setup from
  its README): every video a picker takes (mov, mp4, m4v, qt, mkv, webm,
  mpg, mpeg; `js/media.js` asks the copy of each; 2026-10-22, BE-1) that is
  not already H.264 in an MP4 indexed first
  gets an AWS Elemental MediaConvert job writing `name.web.mp4` beside it
  (H.264, AAC, upright, Rec. 709, fitted to 1080 × 1920 either way up at up
  to 60 fps, never enlarged). It reads and asks; it never deletes, copies or
  touches an original. `{ "all": true }` converts what came before, and
  `{ "all": true, "redo": true }` remakes only copies over the cap. One file
  that cannot be read or asked for is its own `error: …` line, never the
  run's (an upload trigger never fails); a walk stops 30 seconds before its
  time and answers `next`, run again as `startAfter`, and leaves an upload
  under 30 minutes old to its trigger; a size the file does not give is
  asked of MediaConvert's probe, else fitted inside 1920 × 1920
  (`FIT_NO_UPSCALE`); MediaConvert's role writes `content/*.web.mp4` alone
  (2026-11-15, phase 2 audit).
- The viewer's trace (`js/trace.js`, 2026-11-24; the user: option B, "but
  not to overlay the texts"): on a screen of a colleague's personal data
  (a colleague's Personnel pane and the employee record form, the salary
  question, an NRIC copy or photograph, Team's Performance once unlocked,
  a review sheet, My records' Reviews and Personnel) the reader's name,
  sign-in email and the time it was drawn (Malaysia's clock) are tiled
  faintly at -24° over the screen, so a photograph of it names who opened
  it, and its card ends with one line in its layout, above a hairline, at
  the right in 12px mute ink: Viewed by {name} · {date, time} ·
  Confidential (the user, 2026-11-24: "How bout B+C"; its scrolling
  body's end in a sheet). It deters and traces; it is not access control. A screen asks for
  it with `data-trace` (a question with `trace: true`, a file with
  `ADspaceDocs.previewTab(zh, { trace: true })`, read in the panel over
  the page, never a tab); the canvas over it is cleared under every run of
  words and every control, so no word stands on the mark, presses
  nothing, is hidden from a screen reader and never printed, and moves
  nothing. A work screen carries none (`tests/trace.js`).
