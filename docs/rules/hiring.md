<!-- triggers: js/hiring.js js/careers.js js/hrdocs.js js/onboard.js careers/ supabase/functions/hiring-mail -->
# Hiring (`js/hiring.js`, `?s=hiring`; `careers/`, `js/careers.js`, `js/hrdocs.js`; `2026-11-16-hiring.sql`, `2026-11-17-hiring-interviews.sql`, `2026-11-17-hiring-outcomes.sql`, `2026-11-17-hiring-offers.sql`, `2026-11-20-interview-held.sql`, `2026-11-20-hiring-emails-confirmed-cancelled.sql`, `2026-11-20-hiring-before-first-hire.sql`, `2026-11-22-interview-time-pending.sql`, `2026-11-22-interview-time-changed-email.sql`, `hiring-mail`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- Release H2 (HR-SPEC.md in the tests repository, the user, 2026-11-16);
  steps A to D built. Hiring is Team's tab, never a rail section (the user,
  2026-11-16: "one section for people"): `?s=team&tab=hiring`, a candidate
  opened in place (`candidate=`, its pane `ctab=`, Team's strip stepping
  away) with Back to the list, an older `?s=hiring` address opening it.
  The tab and Team are drawn at the granted part `team.hiring` (an admin
  tool, an admin's by itself, held by `team_roles_admin_guard` with
  `team.personnel`) or for a colleague holding a place on a live candidate
  (`hiring_mine()`, read beside `me()`). Search lists Candidates after Team.
- A candidate (`hiring_candidates`, `hiring_people`, `hiring_events`; RLS on,
  no policy, no grant) is added at the part alone (`hiring_add(p_values,
  p_idem)`: name, email, phone, position, source, CV link; one live candidate
  an email, `taken` naming it; the same key twice one candidate), its adder
  its Owner. On a candidate the part adds colleagues as Owner (decides and
  sends) or Interviewer (sees it and scores; stored `interviews`; `hiring_person_set`, told in the
  bell with no candidate's name, `hiring_person_remove` with Undo where it
  happened); a colleague on it sees that candidate alone (`hiring_role`).
  Edit (`hiring_save`, over the row as read, `stale`) and the link
  (`hiring_link`, Reset link) are the part's or the Owner's; an Interviewer
  reads no link.
- The candidate's step (`2026-11-21-candidate-step.sql`; the user,
  2026-11-21): while the candidate's latest step on their page waits on the
  team (`hiring_step`: a time chosen, other times asked for, an offer
  accepted, a contract signed, an offer declined with no offer made since),
  the list's state reads it in amber (`STEP`: Time chosen, New times
  requested, Offer accepted, Contract signed, Offer declined) in place of
  the stage, the record's head keeping the stage; it waits in the
  Dashboard's Waiting for you (`hiring_waiting()`, never an email or a note)
  for whoever may act: the part and the Owners, an accepted offer or signed
  contract the part alone (Confirm is the part's). An invitation's New
  times requested is amber in the record too, as everything waiting on the
  team.
- The list is a card a stage (New first, Removed last and shut); a record
  is Overview (Details, the CV, Candidate page with Copy link and Preview),
  People and Activity (`hiring_events`, never the Activity record: a
  candidate's details reach only the people on it).
- A CV is a link (https) or a file in the private Storage bucket `hiring`
  (20 MB, PDF or Word, `{candidate id}/{time}-{name}`), read by anyone on the
  candidate through a 60-second signed link opened at the press, added and
  removed by the part or the Owner (`hiring_file_ok`).
- Remove (the part) hides a candidate from everyone else and its page, Undo
  where it happened, Restore in its ⋯; Delete once removed, the name typed
  back, takes its people, history and CV file.
- `/careers/?k=` (`careers_read`, anon): at Received, with no interview,
  document or decision, the shared received page (DESIGN.md §4, 2026-11-25:
  Application received, the track to Interview and Decision, Your
  application, Contact ADspace with the careers mailbox and Chat on
  WhatsApp); after it, Your application, the candidate
  greeted by their whole name, the position, the day received and Application
  received; never a colleague, a note or an email; English alone. The link
  ends `hiring_link_days` (30, 7 to 90) after the last step.
- Interviews (step B, decision 2; no slots system): the part or the Owner
  invites from the record's Interview tab with one to three times, all
  within `hiring_invite_days` (14, 1 to 14; the user, 2026-11-17: times on
  several days) of each other, an hour ahead at
  least and 60 days at most, a length (30, 45, 60 or 90 minutes), Google
  Meet or At the office and a note (`hiring_invite`, one key a question;
  `slot-window` naming the days); its question names the online meetings
  already on the shared calendar, by time alone, one row under the times
  (`meet-create` `busy`, 15 days at most, `hiring_busy_may`). A new invitation replaces one still
  open. The candidate picks a time on their page, or None of these times
  with a note (`careers_pick`, `careers_none`, anon, the link's own key,
  refused `not-open` once the candidate is past New, Invited or
  Interview; any decision, Proceed included, cancels an invitation still
  open or answered with other times, 2026-11-24;
  the Owners told in the bell, `hiring.picked`, `hiring.none`, never the
  name). An invitation is answered by its reply-by date (`reply_by`,
  stamped as it is made: the earlier of `hiring_reply_days`, 3, 1 to 14,
  after it and the last time offered; the user, 2026-11-19), which the
  invitation email and the page state; past it, `careers_pick` and
  `careers_none` refuse `reply-passed`, the page reads that ADspace will
  contact the candidate, every read draws it Expired, and
  `hiring_interviews_expire()` (pg_cron `hiring-interview-expire`, every
  fifteen minutes) files it and tells the Owners (`hiring.expired`); the
  console reads Expired with its reply-by and Invite again, an expired card
  holding no ⋯. Approve (`hiring_interview_approve`, the part or the Owner) books
  an online interview's Google Meet (`meet-create` `interviewId`, the event
  `adhire{id}` titled Interview · {position}, never the candidate's name),
  and the candidate moves Invited → Interview. Each step emails the
  candidate (`hiring-mail`: the invitation with a button to their page, the
  confirmation with the Meet or the office's address; from the careers
  sender; filed by `hiring_mail_done`, Email again where it failed). Cancel (asked) takes the Meet off; on a confirmed interview it asks
  Email {name}, ticked (the user, 2026-11-20: "yes fix the 3 hiring issues
  too"): `hiring-mail` `cancelled` (Interview cancelled: {position}, the
  time it held, the earlier Google Meet link no longer applies, ADspace will
  contact them; `cancel_mail`, `not-cancelled` for an interview never
  confirmed, `replaced` once new times are sent), Email candidate on the
  card where it failed; the candidate's page then reads Status Interview
  cancelled and ADspace will contact you to arrange another time., never
  the time or the link (`careers_read` answers `{state: cancelled}` alone),
  until new times are sent.
  The page reads the times offered, then the time chosen, then the
  confirmed time with Join Google Meet or Get directions, never the times
  not chosen. A time chosen and not yet confirmed (`2026-11-22-interview-time-pending.sql`;
  the user, 2026-11-22: "It looks like it is already confirmed") reads
  Status Interview time pending confirmation, Time chosen with its weekday
  and Duration alone, never where: no address, Get directions, Meet link or
  note, `careers_read` answering `picked` with the state, the time, the
  length and online or at the office alone; then This interview time is
  pending confirmation by ADspace. and You will receive an email once it is
  confirmed. Please do not visit the office until then. (online: You will
  receive an email with the Google Meet link once it is confirmed.). To
  change the time, please contact ADspace on WhatsApp. with Chat on
  WhatsApp (`.btn-sm`, the chat mark, `quoteWhatsApp`, never the number)
  stands under a pending and a confirmed interview alike, until it is held.
  Change interview time (the interview's ⋯, group 2, before Cancel; the
  part or an Owner; a time chosen or confirmed, not held) asks one new date
  and time, refusing in place one over an online meeting already on the
  shared calendar (`meet-create` `busy`, this interview's own event
  aside), and `hiring_interview_move` moves it and confirms it (an hour
  ahead to 60 days, `slot-past`, `slot-far`, `held`, `closed`,
  `not-picked`), filed in the candidate's history (never the Activity
  record); online, `meet-create` `update` moves the interview's own event
  (`adhire{id}`, never a second; `create` where only a time was chosen),
  and a move the calendar refuses puts the earlier time back (moved back
  before any email told the candidate, the earlier record returns whole:
  `moved_from_before`). Interview time changed
  (`2026-11-22-interview-time-changed-email.sql`; the user, 2026-11-22: a
  candidate "would have thought the date is the same and maybe missed
  it"): once the move (and the calendar's) succeeds, `hiring-mail`
  `rescheduled` is sent by itself, no tick: Interview time changed:
  {position}, Previous time (no longer applies) and New time, each with
  its weekday (`hiring_when`), where it is held at the new time
  (`{place}`), then, as Interview confirmed now closes too (where its
  template still reads as seeded), If you are unable to attend at this
  time, please contact ADspace to reschedule: with WhatsApp
  (hi.adspace.me/whatsapp, the Short Link to wa.me/adspace) and the careers mailbox (`{contact}`, the database's); its Resend key carries the new time and the move's own moment
  (`moved_at`), so a retry never doubles and a second move emails again;
  sent, it stands as the confirmation (`confirm_mail`) and is filed in
  the candidate's history and the Email log (`hiring_rescheduled`);
  not sent, the card offers Email candidate (the time change, by hand).
  Its template off, the question offers Email {name} for the
  confirmation, as before. The page reads the new time with Rescheduled
  from {previous time} under it (`careers_read` `was`: the time before
  the last move, while confirmed and not held). An office interview holds
  no calendar booking.
  No email before the confirmation names the place: hiring-mail fills
  `{place}` in the confirmation alone, whatever a template holds. Settings, Hiring: Time limits holds the figures
  (`team.settings`) and Interview scorecards the scorecards (the part).
- Interview held (`2026-11-20-interview-held.sql`; the user, 2026-11-20):
  a confirmed interview whose time has begun offers Interview held (the
  part or an Owner, the card's one blue; `hiring_interview_held`,
  `not-yet`, `decided`), asked first with the decision date and time
  prefilled from `hiring_decide_by_suggest()` (`hiring_decision_days`, 7,
  1 to 30 working days, Settings, Hiring: Time limits; Monday to Friday,
  never a day on `public_holidays`, at 6:00pm MYT; `hiring_workday_add`,
  `hiring_decide_by_at`) and Email {name} ticked; the candidate is emailed
  (`hiring-mail` `held`: Thank you for your interview: {position}, the
  date in full, View your application). The interview keeps `confirmed`
  with `held_at`, and is then never cancelled (`held`). The decision date
  is the candidate's (`decide_by`): Change decision date on the card (the
  part or an Owner; never past, 30 working days at most, `past`,
  `too-far`; a note to the candidate, 500) emails the new date
  (`hiring-mail` `moved`, its key carrying the date) and is filed in the
  history; Email candidate stands on the card while its email did not go.
  The candidate's page reads Status Interview held, the interview's date
  and ADspace will inform you of the outcome by {date in full}., never the
  way to join. `hiring_decide_remind()` (pg_cron `hiring-decide-remind`,
  8:30am MYT) tells the Owners two working days before and on the day,
  each once (`hiring.decide_soon`, `hiring.decide_due`, the position
  alone); any decision clears the date and its reminders, and Reopen keeps
  them cleared.
- The Interviewer's Sheet (`2026-11-17-hiring-interview-sheet.sql`; the
  user, 2026-11-17, the team's paper sheet: "a slide window or so so the
  record could stay right"): the Scores tab's Interview sheet opens a panel
  at the right with no scrim (`#hivSheet`, `.sheet-side.is-beside`), the
  record in sight and scrolling beside it: Rating (out of 10), Internal
  remarks, MBTI and the sheet's questions, each saved as it is left
  (`hiring_sheet_save`, one a colleague, filed once when started;
  `hiring_sheet_keys()` the fields, the page's `sheetQs` held equal by
  `tests/hiringsql.js`), then the scorecard and the recommendation, saved by
  Save; `hiring_sheets` (RLS on, no policy, no grant) goes with its
  candidate. Each colleague's scores and sheet are one card on the tab
  (`hiring_sheets_of`).
- Scores and the decision (step C): everyone on a candidate scores them on
  the Scores tab against their position's scorecard (`hiring_scorecards`,
  3 to 8 criteria, one a position, Standard for any other and never
  deleted; `hiring_scorecard_save` / `_delete` the part's), each criterion
  1 to 5 with a recommendation and a note (`hiring_score_save`, one a
  colleague, `incomplete` naming the criterion; Remove with Undo); the tab
  reads every score, its total and each criterion's average
  (`hiring_outcome_of`). The part or the Owner decides (`hiring_decide`):
  Proceed (stage Offer), Keep in talent pool (the candidate asked on their
  page, `careers_pool`, anon: agreed kept `hiring_pool_months`, 12, from
  then; declined closed) or Not proceed (closed); Reopen is the way back,
  Undo where it happened. The decision's note stays with the team; Keep in
  talent pool and Not proceed email the candidate (`hiring-mail`
  `outcome`, a tick in the question, Email the candidate where it did not
  go). `hiring_retention` (pg_cron `hiring-retention`, 03:50 MYT) removes a
  pool agreement past its end, a pool question unanswered within the link's
  days, and a closed or removed candidate after `hiring_keep_months` (12),
  PDPA 2010; their CV files wait in `hiring_files_gone` for the part's
  console to take out of Storage once a visit.
- Offer and contract (step D, decisions 4, 5, 10, 14): the record's Offer
  tab (the part and the Owner alone) drafts the Employment Offer once the
  candidate is to proceed, and the Employment Contract once an offer is
  confirmed, one live of each (`hiring_doc_save`: position, employment
  type, commencement, an end for a contract or internship, probation
  months, days to reply prefilled 3 and 7, the offer's scope, the
  contract's nature of works and place). The salary is `hiring_doc_pay`'s
  alone (RLS on, no policy, no grant), set and read only by the part
  behind the master code (`hiring_unlock`, the Performance unlock's token,
  15 minutes) and the caution step (Sensitive information follows /
  Proceed with caution., Continue); the record reads it Set, never a
  figure, and no list, notice, email, history or search holds it. Send
  numbers it (`ADHR/OFR{YYMM}{NNN}`, `ADHR/EMP{YYMM}{NNN}`, under the
  kind's lock) and emails the candidate (`hiring-mail` `doc`: the
  reference and the day to reply, never the terms). The candidate's page
  lists each by its reference; Read asks a six-digit code emailed to the
  candidate (`hiring-mail` `code`, no sign-in; `hiring_doc_code`, the
  service role's, hashed, 15 minutes, five an hour, the address
  Cloudflare saw; ten wrong codes a document a Malaysian day, over any of
  its codes, answer `locked-today` to both until the next day,
  `hiring_doc_wrong_today`, 2026-11-24), then the caution step, then the terms and salary for
  30 minutes (`careers_doc_open`, a view token hashed); an offer is
  accepted (name typed, the confirmation ticked) or declined (a reason
  optional), a contract signed (name, NRIC or passport number, a
  signature drawn in a 300 by 100 box), the code's email, address,
  country, device and the document's fingerprint kept
  (`careers_doc_answer`), the Owners told. Signed outside the page: Mark
  signed (by scan or on paper, the PDF in the candidate's private folder,
  `hiring_doc_mark`); Send back with a reason keeps the signing in its
  history; Withdraw / Restore while the days run; Replace drafts a copy
  that takes the reference on Send, the earlier one void; Void (the
  part, a reason); Delete a draft, or a void one with its reference typed
  back. Confirm (countersign) is the part's (`hiring_doc_confirm`, a stamp
  certificate number optional, Email {name} ticked: `hiring-mail`
  `confirmed`, {Document} confirmed: {ref}, confirmed and countersigned by
  ADSPACE PLT, read on the candidate's page, no attachment and no salary;
  `confirm_mail`, Email candidate where it failed; 2026-11-20, the page
  having promised it), and the confirmed copy is drawn once
  behind the master code with its Record of this Document
  (`ADspaceHrDocs.seal`, `js/seal.js`), stored at
  `{candidate}/sealed-{document}.pdf` and kept with its SHA-256
  (`hiring_doc_seal`), never drawn again. The PDF (`js/hrdocs.js`) is the
  user's templates in substance, their typos and grammar put right,
  ADspace in place of we and our, the candidate greeted by their whole
  name (no NRIC), Yours sincerely on both, one declaration
  (`ADspaceHrDocs.declare`, the contract's and the page's tick alike),
  the signing block's NRIC or Passport Number, the salary in words and
  figures, the intern and part-time paragraphs only for those types; the
  page and emails read Read offer and Read contract. Its
  documents' files are queued for the console to take out of Storage when
  it goes (trigger `hiring_docs_files_gone`). /verify/ answers an offer's
  or contract's reference once sent as HR Letter (Valid, Void, Withdrawn,
  Declined, Expired), its days and, sealed, its Document ID and Check a
  file, never the person (`2026-11-17-hr-documents-verify.sql`); a
  confirmed one is listed under HR Letters (`hiring_register()`, HR Letters
  at View) and on the colleague's Documents, its ⋯ Download opening the
  sealed copy through a 60-second link (`hiring_file_ok` lets HR Letters at
  View read that file alone).
- Make colleague and onboarding (step E1, `2026-11-17-hiring-onboarding.sql`,
  `js/onboard.js`): a candidate whose contract is confirmed offers Make
  colleague (the part or the Owner, `hiring_hire_state`): one question of
  sign-in email, Employee ID, user group, department, position, first day
  and direct manager, the terms read from the contract and never retyped
  (`hiring_make_colleague`: `not-ready`, `taken` by field, `again` once
  made), writing the colleague, their Personnel record's start, their
  Welcome Kit and their onboarding at once, the candidate Hired
  (`hiring_candidates.member_id`), never a salary. A colleague's record
  draws Onboarding (Personnel or Hiring at Work): the checklist, a row a
  step, what the portal knows ticked by itself (offer, contract, employee
  record, NRIC, Welcome Kit, Handbook files) and the rest ticked by hand
  with who and when (`onboarding_tick`); Assets, each kind, detail, issued
  and returned (`onboarding_assets_save`, over the row as read); Entry and
  exit, each step its own tick. `team_welcome`, `welcome_kit` and
  `team_onboarding` have RLS on, no policy, no grant. A new colleague's
  first sign-in meets the Welcome Kit before the Handbook's files
  (`welcome_kit_mine`, read beside `handbook_due`, holding the gate):
  their first day, Employee ID, department, position, direct manager and
  company email, then the team's sections, the Wi-Fi password and door
  PIN always Please check with your direct manager., and last Working
  hours, the Business setting in force on their first day (Settings,
  Portal: Working hours, `team.settings`; `work_start` and `work_end`
  HHMM, `work_lunch_min`, `work_weekend` 0 Closed, 1 On demand, 2 the
  weekday's hours; `bad-hours` for an end not after its start;
  `ADspaceAdmin.workHours`; `2026-11-20-working-hours.sql`; the user,
  2026-11-20: "Give working hours a setting"), its PDF the same at today,
  never typed into a section; Acknowledge (`welcome_kit_ack`, filed). The
  Employment Contract's Working Hours clause (8 hours a day, five days a
  week, a one-hour lunch, `js/hrdocs.js`) never reads the Working hours
  setting: it stays as written (the user, 2026-11-20: "Maintain employment
  contract", its own sentence allowing the hours to change with business
  needs). The sections are Settings, Hiring: Welcome
  Kit (`team.settings`, `welcome_kit_save`: 1 to 12 sections, `secret`
  refusing a line naming a password, passcode or PIN with a value).
- The candidate emails are automatic emails (`2026-11-21-candidate-emails.sql`;
  the user, 2026-11-21: "the interviews emails ... should all be automatic
  emails", "the process should be continued, just to show an alert"): the
  invitation, confirmation, time changed, cancellation, thank-you and new decision date,
  both outcomes, an offer or contract sent and sent again, its confirmation
  and its expiry. Their words are `hiring_email_templates` (Hiring's
  Edit email templates, Candidates; `team.settings`; each with its own
  switch; fields `template_fields('candidate')`; seeded with hiring-mail's
  words, byte for byte, `tests/hiringmailfn.js`), filled by hiring-mail
  (`fill`: a field left empty on its own paragraph leaves with it). A step's
  email goes only while `hiring_mail_gate` reads the portal's Email,
  Automatic emails and its template on; else the step stands, nothing is
  sent and the email is filed Not sent (`off: Automatic emails are off.`,
  the card then offering Email candidate). Each step's question says so
  first, in a warn line in place of its Email {name} tick (`mailFields`).
  Email candidate on a card and Send again in the Email log are sends by
  hand (`byHand`, `againOf`: the portal's Email, Send by email and the
  group's Send email; `data-gate`). The verification code goes whatever
  the switches.
- No candidate data goes to an AI service, ever (decision 10's rule for
  salary covers every candidate field).
- Hiring records held (`2026-11-17-hiring-records-held.sql`; the review
  since #1134): an Interviewer reads a candidate's CV alone in Storage
  (`hiring_file_ok`), never a sealed contract, scan or stamp; a hired
  candidate, or one holding a signed or confirmed document, is never
  deleted (`hiring_delete` `has-contract`); any outcome but Proceed, Reopen
  included, withdraws the documents still `sent`; a deleted document's
  reference is kept (`hiring_serials_kept`) and never given again; Make
  colleague asks Team at Full Access as Add member does (`team-access`,
  `hiring_hire_state` `may`).
- The Interview Sheet and the Welcome Kit download as PDFs for an admin
  alone, behind the emailed code (`hr_form_pass`, `docs/rules/personnel.md`):
  Download on a candidate's Interviews (the decision, the averages, each
  colleague's rating, scores and answers) and beside Add section in the
  Welcome Kit's sheet.
- Decision dates (2026-11-20, the coordinator's review): a decision date
  is a working day (`is_working_day`, the one rule: Monday to Friday and never
  a day on `public_holidays`, as the front door's Service hours read the
  same table; `not-workday`, Choose a working
  day.); the morning reminder counts the working days left (due tomorrow,
  on the next working day, in 2 working days), and past the date with no
  decision tells the Owners each working morning, once (`hiring.decide_over`,
  `decide_over_on`), until a decision or a new date; the candidate is never
  told it is overdue: their page keeps the date and, once it has passed,
  adds If you have not heard from ADspace by then, please contact ADspace at
  {the careers reply-to mailbox} (`careers_read` `contact`, from
  `mail_sender('careers')`, never typed; the user, 2026-11-20). The
  new date's email reads Decision date updated: {position}, apart from the
  outcome emails. A hiring email sent by a system account (the super
  admin) closes Yours sincerely, ADspace Hiring Team, never the account's
  name over ADspace (`system` from each prepare; no prepare answers the
  colleague's own address).
- Hiring times (2026-11-20): every time a candidate or the team waits on
  (the times offered, a reply-by, the interview, the decision date) reads
  as `ADspaceClock.due` writes it, 21 Nov 2026 (Saturday), 10:00am:
  `hiring_when` in the emails, the bell and the history, the console's
  card and `/careers/`; a time gone by (sent, approved, held) reads without
  its weekday.
- Internship and Part-time contracts carry no statutory contributions (the
  user, 2026-11-20: "intern and part time contracts, all no statutories
  epf, socso eis"): their Deductions clause names no EPF, SOCSO or EIS, and
  reads The Employee shall not be entitled to contributions under the
  Employees Provident Fund Act 1991, the Employees' Social Security Act 1969
  or the Employment Insurance System Act 2017.; a full-time contract is
  unchanged. No template bracket or field mark is left in print (the
  items [a], [b] … aside).
- Before the first hire (2026-11-20, the user: "Check before the first real
  hire: these parts, fix all"):
  - every reply-by, an invitation's and an offer's or contract's, ends at
    6:00pm Malaysia time on its day (`hiring_day_end`; an invitation never
    past its last time offered), written with its weekday and time;
  - every line on the candidate's page asking them to contact ADspace names
    the careers mailbox (`careers_read` `contact`, on every answer, a
    refusal's too; `mail_sender('careers')`, never typed), and every
    candidate email replies to it: the HR mailbox (hr@adspacestudios.com,
    Settings, Messages: Reply-to mailboxes; the user, 2026-11-20);
  - Keep in talent pool and Not proceed email the candidate only once their
    Undo's 30 seconds pass with no Undo (the user; this act's own window,
    `ADspaceAdmin.undoHere`'s `ms`, every other Undo keeping 8): the email
    is queued in the database, never timed in the tab (2026-11-24, the
    review: a tab shut in those seconds sent nothing;
    `hiring_outcome_mail_queue`, due 30 seconds on, read Queued; sent by
    hiring-mail's drain, woken every minute while one is due,
    `hiring_outcome_mail_claim` and `_close`); Reopen (Undo, filed only
    once the database holds it) cancels it, and a decision reopened is
    refused the email (`no-email`); the decision is asked first, and the
    Google Meets of the interviews it cancelled (`hiring_decide` `meets`)
    are removed after it, never before;
  - Proceed promises no offer: the page reads ADspace will contact you
    about the next step. (Status Application in progress) until an offer is
    sent; a candidate who declined the talent pool reads ADspace will not
    keep your details on file.;
  - Send new times on a confirmed interview not yet held asks first and
    cancels it, its Meet taken off where the calendar allows (else the team
    is told to remove it; the candidate's email says the link no longer
    applies) and the candidate emailed; Keep in talent pool and Not proceed
    cancel it too, its Meet with it (`hiring_invite`, `hiring_decide`);
  - an offer or contract past its reply-by with no answer is filed once
    (`hiring_docs_expire`, every fifteen minutes) and the candidate emailed
    by `hiring-mail`'s drain (woken by the database with the wake secret;
    `hiring_expire_mail_claim` takes each row once), and its Owners told
    once (`hiring.doc_expired`, An offer or A contract expired with no
    reply); a declined offer tells them once too (`hiring.declined`): each
    through `hiring_tell_once`, `dedupe_key` `{kind}:{document}:{colleague}`,
    the notice opening the candidate, never its name
    (`2026-11-21-offer-declined-or-expired-told.sql`; the user, 2026-11-21:
    "yess", reversing 2026-11-20's email alone);
  - Make colleague carries the confirmed contract's salary into Personnel
    (trigger `hiring_candidates_pay_to_personnel`; never a figure on screen
    or in a history line; a salary already set is left alone);
  - the employment type reads in words (Permanent, full-time), and a
    document sent back carries its reason in the email.

- A colleague's interview sheet and scores are one card and are taken off as one (`hiring_sheet_remove`, 2026-11-23, the user: "interview sheet couldnt be deleted"): one's own from its ⋯, Remove with Undo where it happened (the sheet and the scores written back); another colleague's by the candidate's Owner or an admin, Delete, asked first; never once the candidate is hired or closed. Filed on the candidate.
