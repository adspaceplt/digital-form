<!-- triggers: js/campaigns.js js/creators.js js/creator.js js/decide.js creators/ creator/ supabase/functions/creator-mail -->
# Creators (`js/campaigns.js`, the section once named Creator Campaigns), the creator portal

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- Booking steps:
  - Confirmed → Pending visit → Pending draft → Submitted → Reviewing →
    Changes requested → Scheduled → Posted → Completed, each gated by its data,
    each with Revert.
  - Withdraw / Replace / Reinstate in the ⋯.
  - Deleting a campaign or a creator takes the name typed back; every
    campaign write takes `.select('id')` and names a refusal (Confirm
    creators counts the bookings not confirmed).
  - In production and Completed are derived (`syncCampState` off
    `loadOptions`): every booked creator at Completed completes the
    campaign, one reverted puts it back in production, none open returns it
    to Open, and an Open campaign whose bookings fill every slot again (a
    creator reinstated) is in production; filed `campaign.stage`. Nothing
    presses it. Open with bookings and a free slot is a reopened selection.
- Release to client (Submitted → Reviewing) goes only through
  `campaign_qc_pass(p_option, p_want_second)`. A trigger refuses any other
  route.
  - Nine required checks in three groups, kept per booking (`qcKept`) until
    release. The list scrolls in `.sheet-body`, with `.qcfoot` fixed.
  - Tick all (`#qcAll`) above them ticks or clears the nine and reads mixed
    while only some are ticked.
  - A second reviewer is optional and never assigned: anybody but the asker
    completes it (unique `(option_id, team_member_id, round)`).
  - The ask is outstanding only while `qc_second_wanted && checks < 2`. The
    asker is the earliest check.
  - A send-back is checked from the top (`revision_round`).
  - `.qc-hold` names who checked. No notification.
  - The sheet reads the request the file answers and its caption first
    (`#qcCap`; `No caption.` in warn when there is none).
  - A file added or removed while Submitted voids that round's checks
    (`option_qc.voided_at`, trigger `campaign_deliverables_qc_void`); the
    same colleague's check is taken again (`2026-10-10-released-files.sql`,
    audit S5).
  - Release stamps `campaign_options.released_round` (the newest round
    handed in), and `get_campaign` sends that round's files alone, never a
    round handed in after the client asked for changes until it is released
    in its turn, never a hidden file.
- Every decision on a draft is a row in `option_reviews`, told apart by
  `source` (client, team) and never removed (`undone_at`, `undone_by` when
  taken back): the client's through `review_draft`, the team's send-back
  through `campaign_send_back` (a note required; the round moves on), and
  the team's approval for the client through `campaign_proceed`.
  - At Reviewing the card offers Confirm internally (asked first) in place
    of the plain step forward: a `source` team approval under the
    colleague's name. `get_campaign` sends it as `by_team`, and the client's
    page reads Confirmed by {name}. Revert out of Scheduled is
    `campaign_revert_approval` (the approval kept, undone). The card names
    who approved (`.kapproved`).
  - A booking reaches Scheduled from Submitted, Reviewing or Changes
    requested only while its latest decision not taken back is an approval
    (trigger `campaign_options_approval_gate`, `needs-approval`; audit
    2026-11-15); a move back from Posted or Completed is untouched.
  - The card shows the open request (Changes requested, who, when, the note)
    and, once the creator hands in again, what it answered (Asked for;
    `requestHtml`). A team round from before the record is `drop_reason`.
  - Revert out of Changes requested is `campaign_revert_changes`: the
    client's back to Reviewing on the round last checked (refused
    `new-files` once the next round is handed in), the team's back to
    Submitted. A plain write into Reviewing is refused by the release gate.
  - `get_campaign` counts the client's own rounds only and never shows a
    request taken back. The client's page shows no round count.
- A handed-in draft always shows its caption field, with `No caption.` in
  warn when it is empty.
- A booking card has one Save: its notes and link, then each placement
  whose results moved (2026-10-20, CMP-5); from Scheduled on it offers no
  hand-in guide or link to paste (CMP-4), and Release to client says
  Released to the client. on the card (CMP-6). Its actions stand at the
  card's foot, after Results, reading Revert, Request changes, Save, then
  the step forward at the right edge (its own row on a phone); an empty
  note is a quiet Add note growing into the box, a result figure reads
  with its separators, and every step taken on a card is answered on that
  card (`cardSay`), never in the head (2026-10-22, CMP-7, CMP-10, CMP-16,
  CMP-M2). Bookings and the Schedule list booked creators alone, a
  shortlisted one staying on Selection (CMP-13). The record says post,
  never publish, of a booking's date: Post date, Next post date, Posted on
  (CMP-11); a time reads 2:00pm (CMP-12). On a phone a move that is not the
  blue Publish (Unpublish, Reopen selection, Resume campaign) is the head
  ⋯'s lifecycle item (`#campLifeItem`), never a row above the tabs (CMP-M1).
- A booking's plan (date, a time picker, location, contact, phone, or the
  tracking no.; draft due; post date) is written only on the Schedule,
  saved on change and filed with what changed. The card reads it
  (`planFacts`, Edit in Schedule) and keeps only the notes. The creator's
  page shows location and contact. The Schedule is the Creators tab's
  register (`.bookreg.sched-reg`): Upcoming then Past, a folded row a booking
  (name, shoot date and time, post date; Not set where none; where the
  head is hidden each date leads with its head's word, Shoot or Delivery,
  Post date; on a narrow pane each date its own line under the name), the plan's
  fields opening under the row on the name's x; a booking stays open through
  a save, and a lone booking opens by itself. On a phone Draft due and
  Post date share a line.
- The client's selection closes by trigger the moment the bookings fill the
  slots (`campaigns.selection_closed_at`); only Reopen selection clears it,
  offered only while closed with a free slot, whether the campaign is Open
  or In production (every booking reverted puts it back to Open, still
  closed; 2026-10-10). While closed, `save_selection`
  and `confirm_selection_with` refuse (`closed`), except backups where opened and
  every slot is taken. The Creators tab folds options and backups under Not
  selected (`#campUnpicked`) while closed.
- The one stage step in blue on a card is Release to client; every other
  step, and every Save on the card, is tonal. A shoot date moved moves Draft
  due only while it is empty or still the old date plus 7, said on its row
  (2026-10-15).
- Each booking's card names its step under its head (`.kcard-steps`), the
  client's six steps as the selection page draws them (`ADspaceIcons.journey`,
  `stepOf`), a delivery campaign's own; none before the creator is booked
  and none once Completed. On a phone a booking's head is two lines: the
  name (one line, cut with an ellipsis) with its link and ⋯, then the
  state (its dot and whole word, never shortened) at the left and its date
  at the right (the user, 2026-10-15; `tests/geom.js`). A completed campaign offers no state move (no
  Resume, no Unpublish: its link stays live for the results).
- `submitted` opens by itself and carries `.is-waiting`.
- A video plays (`.filecard-video`, 9:16, black ground). Media are 9:16 cards;
  anything else is a `.filepin-row` line.
- The team hands a file in for a creator (`teamDeliver()`, at pending draft /
  changes / submitted), with `campaign.file_added`. 1 GB per file
  (`ADSPACE_CONFIG.s3.maxUploadMB` 1024). Picked files are held on the card
  (`teamHeld`, × each) and upload only on Hand in N files.
- Removing a handed-in file arms first (`.filearm`), then soft removes, then
  offers Undo in place, until the client approves (audit S6, the user,
  2026-10-10). From Scheduled on a file is the client's record: its control
  is Hide from the client (the struck eye; `campaign_file_hide`, Creator
  Campaigns: Campaigns at Work, client scope, filed `campaign.file_hidden` /
  `campaign.file_shown`, Undo where it happened), it waits under Hidden from
  the client (`details.filehidden`, Restore, never asks), and only the granted
  part `campaigns.files_delete` deletes it, once hidden, from its ⋯
  (`campaign_file_delete`, asked, `campaign.file_deleted`; the stored file
  is kept). Trigger `campaign_deliverables_guard` (as the caller) refuses a
  page removing an approved file (`approved-hide`) or setting the hidden
  columns (`hide-function`). `campaign_deliverables` reads at Campaigns View,
  adds and changes at Work and deletes at the part, four policies.
- A campaign name that would render as nothing reads `Untitled campaign` and
  stays editable. A new one is refused on save.
- The campaign's form is one sheet for New campaign and Edit (`#addCampBox`);
  the record's ⋯ holds Edit and Delete, last.
- The campaign record:
  - Its panes (`pane=`) are Overview, Creators, Schedule, Selection,
    Finance, Activity; the address's pane is read before the address is
    written, and a new campaign opens on Creators (2026-10-27, CMP-17,
    CMP-18).
  - A draft with no creator draws no Publish and Add creators is its blue,
    the empty list offering no second one (2026-10-20, CMP-1).
  - Below 1100 Details, Key dates and Timing follow the pane (`.rail-after`);
    Selection stays before the tabs (CMP-2).
  - Selection is a view over the bookings. It never writes.
  - `.camp-next` is derived on every repaint.
- Next shoot means the earliest date from today; if none, the row reads Last
  shoot.
- `nextAction()` counts undated / upcoming / passed Pending visit bookings
  correctly.
- `#bulkBox` moves under the head that asked for it (`bulkOpen(btn)`).
- Events are filed under the campaign's raw title (`logSubject()`), with the
  creator named in the detail.
- The invoice fold arrives with the first confirmed creator and leaves with the
  last.
  - One Save covers the number (`AINV` + six digits) and the PDF.
  - With `ADSPACE_CONFIG.s3.privateInvoices` on (after
    `docs/S3-STORAGE.md` §5), the PDF is signed under `private/` and the row
    keeps the key, never an address; View invoice and the client's PDF link
    ask `sign-download` for a five-minute link, the file found from what the
    caller may read (the campaign row; `get_campaign` for the client's key),
    never from a path the browser sends, and only a key under the campaign's
    own client's folder (`private/{client id}/`; `tests/signdownloadfn.js`).
    The link is a CloudFront signed URL on
    mycdn.adspace.me while `cf_private_ready` is `on` in `app_secrets` (on
    since 2026-10-03, `docs/S3-STORAGE.md` §5d), else an S3 presigned one. An older invoice keeps its public
    address. A refused open on the client's page is one line in its
    language (`#amountMsg`).
  - Remove PDF, with Undo.
  - `get_campaign` withholds `invoice_no` and `invoice_url` until a creator is
    confirmed.
- Confirm creators is reachable from Client selection, from the Creators tab
  (`#campLock2`), and from the header line's Review and confirm (`#campNextGo`).
- Confirming is one act a press (audit F1, S3, C1;
  `2026-10-10-confirm-once.sql`): the selection page's Confirm sends the
  creators on screen, the rate shown for each and a key made as its sheet
  opens to `confirm_selection_with` (anon; `empty`, `closed`, `over-slots`,
  `stale`, `prices` with the rates now), which saves the selection and files
  the confirmation with what was confirmed (`snapshot`) in one transaction;
  a refusal for rates or creators reads the campaign again under the open
  sheet, said in the client's words. The console's Confirm creators is
  `campaign_confirm_creators` (Creators at Work, client scope;
  `stale` with the count): the confirmation, the bookings and the campaign
  move together, filed `campaign.locked`. The same key again answers `again`
  and files nothing. The older `confirm_selection` is dropped (2026-10-26).
  `get_campaign` sends the client's last confirmation (`campaign.confirmed`:
  person, time, the creators chosen); while the picks match it the bar reads
  Confirmed by {name} on {day} with no Confirm (2026-10-15).
- A campaign never books more creators than its slots
  (`2026-10-18-slots-hold-their-bookings.sql`): `confirm_selection_with`
  and `campaign_confirm_creators` refuse `over-slots` (with `slots` and
  `booked`) where those booked (`campaign_booked`) and those confirmed now
  pass the slots, and trigger `campaigns_slots_floor` refuses slots below
  the bookings (`slots-booked`), whoever writes them. The selection page
  reads `over-slots` in its own words with how many may still be chosen
  (`overSlots`), shuts the sheet and rests Confirm while the picks and the
  bookings pass the slots (2026-10-20, SEL-1). The autosave
  (`save_selection`) counts the booked alike (`over-slots`, 2026-10-26).
- A client's confirmation is the record of what was accepted
  (`2026-10-18-confirmations-kept.sql`): `campaign_confirmations` is
  written by `confirm_selection_with` and
  `campaign_confirm_creators` alone (its insert, update and delete policies
  admit nothing), keeps the campaign's title and client (stamped on insert),
  and has no foreign key, so a deleted campaign leaves it. A campaign's
  delete is filed by trigger `campaigns_deleted_log` (`campaign.deleted`,
  the title and invoice number); the page files nothing.
- Timing (`paintCampTiming`) is read from `campaigns.state_log`,
  `campaign_confirmations.created_at`, `confirmed_at` and `completed_at` (all
  stamped by triggers). A stage it cannot date is left out.
- Creator and campaign IDs (`2026-11-08-creator-and-campaign-ids.sql`; the
  user, 2026-11-08: "USE ADCXXXX for adspace creator, ACC for each creator
  campaign", "dont hardcode anything"; the prefix CC since the same day: "just do CC not
  ACC else its pretty long"): every creator a Creator ID
  (`creators.creator_code`) and every campaign a Campaign ID
  (`campaigns.campaign_code`), given by trigger on insert from `id_formats`
  (RLS on, no policy, no grant: a prefix, a width and the next number a
  kind, `id_take` under the row's lock, a code held passed over), never
  changed after (`code-fixed`); a booking's Job reference is the pattern
  (`{creator}/{campaign}`) filled with the two, worked out on read
  (`campaign_job_ref`, the console's `jobRef`). Settings, Clients: Creator
  and campaign IDs (`team.settings`; `id_format_set`: `bad-prefix`,
  `bad-width`, `bad-next` with the `top` in use, `bad-pattern`; filed
  `team.changed` under Creator and campaign IDs) applies to the next one made. The
  Creators List reads the Creator ID under the name (searched), the
  campaign head leads its meta with the Campaign ID, a booking's Terms line
  the Job reference as a copy control.
- Creator payment details (`2026-11-08-creator-payment-details.sql`; the
  user, 2026-11-08: the AP01 form's fields, asked once from the first
  booking, a change going back for approval, "dont hardcode anything"): the
  creator's page holds one Payment details card (`#payBox`, under the head)
  once a booking is Confirmed or later, never a step of a booking, in place
  of the AP01 link. Its sheet (`#paySheet`) asks Billing as (Malaysian
  NRIC, Passport, Company BRN) and its number, the legal name, TIN
  (optional), the billing address, Currency (MYR, SGD) and the methods it
  takes (Bank transfer, DuitNow, Touch 'n Go eWallet; Bank transfer,
  PayNow), the bank (the supplier form's list for that currency), the
  account and its holder (the legal name itself, read only: the bill and
  the transfer go to that name; `creator_pay_check` sets it and opens every
  word of the name on a capital, the rest as typed; 2026-11-13), email, WhatsApp and the confirmation tick, in
  English and 中文; checked as `creator_pay_check` checks it, refused by
  field. Each set is a `creator_pay_requests` row (RLS on, no policy, no
  grant) under a reference from the pattern on the creator row of
  `id_formats` (`{creator}/R{nnn}`, ADC0001/R001; Settings' Creator and
  campaign IDs, `bad-request-pattern`). `creator_pay_form` and
  `creator_pay_submit` (anon, the creator's code counted as `get_creator`
  counts it; `not-due`, `bad` with `field`, `too-many` past five a day)
  answer the ID and account numbers by their last four alone; one left
  blank keeps the number held where its kind, or its method, bank and
  currency, did not move. The rest the link answers masked (the name and account
  holder a letter a word, the email its first two and last letter, a
  number its first two and last four digits, the address its last part,
  the TIN its last four; `creator_pay_masked`,
  `2026-11-10-creator-page-details-masked.sql`; the user, 2026-11-10: a
  link can reach others): each field opens empty, and left blank keeps the
  one held. The console, the emails and the sheet read them whole. A set sent while one is pending withdraws it.
  Details brought in from the AP01 form (`2026-11-10-creators-from-ap01.sql`,
  its SQL Editor part letting the column be empty; the user, 2026-11-10)
  are filed approved (`source` `import`) where Bukku already paid the
  creator, and may hold no billing address: the creator's page then opens
  on Payments once and asks the address alone (`creator_pay_form`
  `address_needed`, `creator_pay_address`, anon: `bad`, `not-needed`),
  kept on the set approved with no approval again, filed under Creator
  page; the console reads Billing address Not set and Source Imported from
  AP01 form. The form's last section, e-Invoice, says each payment's
  e-Invoice to LHDN is issued with these details, above the tick.
  Set inactive asks a reason (`creators.inactive_reason`, Blacklisted;
  held to inactive creators by a check), read on Overview; Set active
  clears it. `profile_of` reads a rednote search
  (`rednote.com/search_result?keyword=…`) as a profile with no handle.
  The console: the Creators List names a creator whose details wait
  (To review), their page's Payment pane holding them (`creator_pay_list`,
  Creators List View; the numbers whole only at the granted part
  `campaigns.pay` View), Add details, else Edit, in its head at its Work
  (`creator_pay_add`, `2026-11-12-creator-details-added-by-team.sql`; the
  user, 2026-11-12: "straight approval (but mark as internally added?)"):
  the creator's fields checked as their own, a number left blank keeping
  the one held, saved approved at once (`entered_by`, read Source Added by
  {name}), the sheet taking it as any approval; where it replaces details
  on file and something changed, Details changed and `creator_changed` go
  to the email and WhatsApp on file as on the creator page (`changes`,
  `prior_id`; `2026-11-24-saved-whole-and-told.sql`), else no email;
  Approve and Decline in its head (a reason the
  creator reads) at its Work (`creator_pay_decide`: `denied`, `decided`,
  `no-note`; filed `creator.updated`); the newest approval is paid to, the
  one before it Replaced. `?s=campaigns&tab=roster&pay={creator}` opens
  their page on Payment. A set sent to review tells the Marketing
  department who can open the Creators List, an admin among them, in the
  bell and on their phone (trigger `creator_pay_requests_notice`, kind
  `creator.details`, opening its row in Payments in place; the user,
  2026-11-13: "these should land to Marketing Department personnel"), and
  the sets waiting are counted in red on the Creators rail row,
  the Creators tab and the phone's tab (`creator_pay_states`, read on
  sign-in and with the Creators List; `ADspaceAdmin.payStates`). A notice
  linking a console page opens it in place, never a second console.
  The emails (`creator_emails`, RLS on, no policy, no grant) are queued in
  their templates' words (`creator_email_templates`: Details received to
  the creator, Details to review to the finance address with the account's
  last four, each change and the console link, Details approved to the creator,
  Details changed to the email on file (never the new one) where a set
  sent on the creator page changes the bank account, the account holder,
  the email or the WhatsApp of the set approved last, naming the day in
  English and Chinese, with the WhatsApp template `creator_changed` to the
  number on file (`creator_pay_changes`, the request's `changes`, read on
  the record and the review sheet; 2026-11-24, the code review); each
  sent or not; Creators' Email templates, `team.settings`) and
  sent by the `creator-mail` edge function (woken by `creator_mail_kick`
  with the wake secret, and by pg_cron `creator-mail-drain` every five
  minutes while one waits; `creator_mail_claim`, `creator_mail_done`, the
  service role's alone), from the creators' sender;
  Resend's word, the sweep, the twelve-month clearing and Messages' Email
  log take them as every other email.
- Creator payments (`2026-11-09-creator-payments.sql`, its SQL Editor part
  `-editor.sql`; Creator R3, the flow the user approved 2026-11-08): a
  creator is a Bukku supplier contact (`bukku_links` kind `creator`), sent
  or linked from the payment details approved last on the Payment pane's Bukku
  band (the Creator ID in Bukku's Creator ID field, chosen beside the
  Client ID and Supplier ID fields in Settings, Accounting, Bukku, else the
  Supplier ID field while none is chosen, `bukku_settings.field_creator`,
  `2026-11-10-bukku-creator-id-field.sql`; the ID number at
  `campaigns.pay` View alone; read at the Creators List, sent, linked and
  unlinked at `campaigns.pay` Work, filed `creator.updated`). The move into
  Posted stamps `campaign_options.posted_on` (the first post's day, else
  today) and `pay_by` (`creator_pay_days_myr` 10 or `creator_pay_days_other`
  21 working days on, by the approved details' currency; Settings, Clients:
  Creator payments) and queues Payment request to the finance address and
  Post recorded to the creator, with the bell (`creator.payment`, opening
  its row in Payments) for
  `campaigns.pay` Work, once a booking (trigger `campaign_options_posted`,
  `_posted_mail`). The team puts the Job reference in the Bukku bill's
  reference; `bukku-sync` `bills` (Read from Bukku on the sheet's Payments,
  and every night after the billing read, `creator_bills_due`) reads the
  creator contact's purchase bills into `creator_bills` (RLS on, no policy,
  no grant; `creator_bills_take`, the service role's), each matched to the
  booking whose Job reference or earlier job its reference or number holds:
  a read of one contact marking gone only that contact's bills, never those
  of the creator's other payment details (`2026-11-25-creator-bills-gone-by-contact.sql`);
  Processing while a balance stands, Paid at none, a bill read with no
  balance keeping the state it had, never marked by hand; Payment sent goes
  once, when a bill read Processing is read Paid, or a bill first read paid
  on a booking posted in the portal (`posted_on`), never for one from before
  the portal; a paid bill keeps the day of Bukku's payment voucher
  (`creator_bills.paid_on`, the latest payment `bukku-sync` reads applied to
  it, ten bills a run), else the day the portal first read it paid; one fill for every creator email's fields (`creator_mail_fill`). A booking given an AKJ number on the
  AP01 form carries it (`campaign_options.earlier_job`, the row's pen at
  `campaigns.pay` Work; `creator_earlier_job_set`: `bad-ref`, `taken`);
  bills matching no booking read under Earlier payments
  (`creator_bills_list`, Creators List View, amounts at `campaigns.pay`
  View). The three emails' words are Creators' Email templates,
  Payment request to Details to review's finance address. Post recorded and Payment sent
  end in one button to the creator's own page (View booking, `#b=` the
  booking; View payment, `?tab=payments`; on their code, `PORTAL_URL`),
  the others in none, and the page keeps the pane and booking a link names
  as it drops the code (the user, 2026-11-10: "A").
  Earlier jobs (`2026-11-11-creator-earlier-jobs.sql`; the user,
  2026-11-11: a past KJ number had nowhere to go without a booking): the
  Payment tab lists a creator's job IDs from before the portal
  (`creator_earlier_jobs`, RLS on, no policy, no grant; one live row a job
  ID across every creator and booking, `taken`, each write under the job
  ID's lock), Add earlier job ID and a row's ⋯
  Remove with Undo where it happened (`creator_earlier_job_add`,
  `creator_earlier_job_remove`, `campaigns.pay` Work, filed
  `creator.updated`), each with the bill holding it (`creator_bills_list`
  `past`), Earlier payments keeping the bills nothing holds. A creator
  with no details approved is linked to Bukku all the same, nothing sent
  (`2026-11-12-creator-linked-by-earlier-job.sql`; the user, 2026-11-12:
  KJ3105 on Gaby Low, her Bukku contact Low Chee Guan): the Payment pane's
  band reads Link to Bukku, its sheet offering the contacts of every
  purchase bill whose reference or number holds one of the creator's
  earlier job IDs (Bill for KJ3105) before those of the same name, never a
  new contact (`bukku_creator_link_prep`, `bukku-sync` find and link); a
  link reads the creator's bills at once, the night reads a creator an
  earlier job awaits (`creator_bills_due`), and an earlier job or booking
  of a creator not linked reads Not linked, never Not billed.
- Payments (`tab=payments`, `2026-11-13-creator-payments-queue.sql`; the
  user, 2026-11-13, approving mockups/creator-payments: one creator at a
  time "won't scale"): Creators' third tab, at Creators List View,
  every creator's payment work in one read (`creator_payments_queue(p_paid_from)`):
  Details to review first (Review opens `#cpqSheet`: the set, what changed
  against the approved one, the bookings waiting; Approve and Decline at
  `campaigns.pay` Work through `creator_pay_decide`), then Ready to bill
  (posted in the portal, no live bill; Create bill as the creator's page,
  Link to Bukku opening their Payment pane where they are not linked),
  Draft in Bukku, Awaiting payment (past Pay by in red, the card counting
  it) and Paid, a bill paid within the period, Open in Bukku on its row as
  an awaiting bill's; a card none of whose rows holds an act gives up the
  act's track, so its figures end on the card's edge (2026-11-19) (`#cpqPeriod`: Last 3 days,
  Last 7 days, This month and last month by default, Last month, Last 3
  months, This year; kept in this browser, `adspace-cpq-period`); the tab
  counts in red what waits (details to review, bookings ready to bill);
  the client, campaign and currency pills and the search filter every
  group; Create n bills (those with a fee) and Read from Bukku (each linked
  creator in the queue, one after another) at `campaigns.pay` Work; the fee
  and every amount at `campaigns.pay` View alone; `row=` (a booking or a
  set of details) opens its row, ringed (`tests/payqueue.js`).
- The campaign record carries no creator payment figure, so it can be
  shown to a client (the user, 2026-11-25): no booking's payment or bill
  chip, no Open in Bukku in a booking's ⋯, no Creator payments rail block,
  no creator fee, margin or paid figure on any of its panes; its figures
  are the client's alone (the amount, SST, Total, the invoice). A
  creator's payment work stays on Creators > Payments and the creator's
  own page (Payment, Totals). `campaign_creator_bills(p_campaign)`
  (`2026-11-22-campaign-creator-payments.sql`) is left in place and
  called by no page (`tests/cpaycamp.js`).
- Creator fees (`2026-11-13-creator-fees.sql`; the user, 2026-11-13: "no
  show amount just internal records creator records and bukku bill for
  payments"): the fee agreed with the creator a booking, in their payment
  currency (`creator_fees`, `creator_bill_claims`; RLS on, no policy, no
  grant; no standard fee is offered, the user, 2026-11-13: "lets not set a
  standard"), set on the Payment pane's booking pen, or typed into Create
  bill's question, at `campaigns.pay` Work (`creator_fee_set`:
  `bad-amount`, `billed` once a bill or a claim under ten minutes holds it;
  filed `creator.updated` from and to), a fee read from a bill Bukku holds
  (trigger `creator_bills_fee`, backfilled); answered at `campaigns.pay` View
  alone (`creator_bills_list` `fee`, `standard_fee`; `creator_totals`
  `agreed`, `owed` (no paid bill) and `margin` (client rate less the fee in
  one currency, an admin's alone: `perf_is_admin()`,
  `2026-11-13-creator-margin-admins.sql`)), never to the creator's page or a client. Create bill (a
  booking Posted or Completed with no bill, the creator linked, the account
  chosen; it asks the amount, the fee written in, and keeps it as the fee
  first) and Create n bills (those with a fee) (`bukku-sync` `createbill`, `options` a run of twenty at most in one call, its product, accounts and each creator's bills read once a run; 2026-11-25):
  `creator_bill_prep` as the caller (`not-posted`, `no-fee`, `not-linked`,
  `billed`, `no-account`, `no-item`, `no-fx`, `creating`, the claim taken), Bukku
  searched for a bill whose reference no. or reference is the Job reference whole, never one holding it inside a longer one (`ADC0001/CC1001` is not `ADC0001/CC100`'s; `in-bukku`, never a
  second), then one bill on credit, a draft with e-Invoice action NORMAL,
  the Job reference in its reference no., its description `{campaign} ·
  {creator}`, one line at the fee: the Bukku product of the item SKU found
  through Bukku's products (its base unit), the line `KOC Fee - Client:
  {brand} ({campaign}) ({creator})`, the classification code and the account
  found by its code in the chart of accounts (Business settings
  `bukku_settings.bill_item_sku`, `bill_class_code`, `bill_account_code`,
  seeded once P995, 037 and 6000-03, Settings, Accounting, Bukku, `bukku_bill_set`;
  `no-product`, `no-bukku-account` before anything is sent, the claim let go;
  `2026-11-15-creator-bills-koc-fee.sql`; the user, 2026-11-15), no tax, due
  on `pay_by`; read back as Read from Bukku reads,
  `creator_bill_done` letting go of the claim and filing the number; a bill
  made whose list is not read back is filed by `creator_bill_made`, its claim
  kept ten minutes more, and a bill sent and unanswered is `not-confirmed`,
  its claim kept, said as Bukku did not confirm, never Not created
  (`2026-11-25-bukku-made-once.sql`). A
  draft is kept as one (`creator_bills.status` `draft`,
  `2026-11-13-creator-bill-drafts.sql`), the booking reading Draft in Bukku
  until it is posted there; each bill's ⋯ holds Open in Bukku (`billlink`); a bill the portal made
  is held to its booking by Bukku's own bill ID (`creator_bills.made_for`,
  `2026-11-13-creator-bills-by-bukku-id.sql`), whatever its reference reads
  later, until Bukku no longer lists it (voided or deleted), which frees the
  booking for Create bill again.
- Creator payments sheet (`2026-11-09-creator-payments-sheet.sql`, Creator
  R4; the user, 2026-11-08: the payments spreadsheet, the full bank number
  in it): a set of payment details approved while the sheet is on is
  queued once (`creator_sheet_rows`, trigger `creator_pay_requests_sheet`)
  and added by `creator-mail` on its wake as a row of the finance team's
  Google Sheet, each value under the header that names it (`COLUMNS`,
  `columnsOf`: every word of a name in the header, the longest name first,
  each value once; a header naming none left empty), the numbers whole;
  claimed and closed by the service role (`creator_sheet_claim`,
  `_done`), a row refused tried again at the next wake, five tries (one
  never tried, its run out of time or the sheet unread, put back with its
  try given back, `creator_sheet_release`; one Google may have taken, an
  append that timed out or met a 5xx or a row left at Sending ten minutes,
  failed Not confirmed and never tried again by itself nor queued afresh,
  so the bank details are never added twice (audit 2026-11-15); every other
  refused row queued afresh when the sheet's setting is saved; Google asked
  with a 20-second limit); nothing
  claimed while `GOOGLE_SHEETS_REFRESH_TOKEN` is unset
  (`docs/GOOGLE-SHEETS-SETUP.md`). Settings, Clients: Creator payments sheet
  (`team.settings`; `creator_sheet_get`, `creator_sheet_set`: a Sheets link
  read for its ID, `bad-sheet`, `bad-tab`; filed under Creator payments
  sheet), whose save asks `creator-mail` `check` (as the colleague) how
  many headers will be filled. The pay sheet reads each set's Creator payments sheet
  line (`creator_sheet_state`).
- The Creators List:
  - A row is one button opening the creator's page (2026-11-10, the user:
    "only an open button then inside contains all their information (like
    clients / suppliers)"): Creator (name over Creator ID) · Platforms (words,
    never links) · Campaigns · Client rate · the chevron; the payment
    details after the name (the user, 2026-11-12: the column read Approved
    for good): approved a green dot alone (`.cr-paydot`, named Payment
    details approved on hover and to a screen reader), To review and
    Declined as their dot and word, nothing while not submitted; no ⋯ and
    no profile link on the row. On a phone two lines: the name with that
    mark, then Creator ID · platforms · campaigns (one line, cut at its
    end) with the rate. A Payment details filter
    (`#rosterPay`: Not submitted, To review, Approved, Declined). The
    figure is the client's price with markup, never the creator's payout, so
    it is never headed Fee.
  - A creator's page (`#crRec`, `creator=` and `pane=` in the address, the
    list and its bar stepping away; search opens it): Back, the record head
    (the name over Creator ID · platforms, Active or Inactive, one ⋯ of Reset
    link, Set inactive or Set active with Undo where it happened, Delete),
    the view strip and a pane: Overview (Details: Creator ID, then Name,
    Client rate, WhatsApp and Notes each changed where it is read, its pen
    (Notes in a box of lines, keeping their breaks),
    filed `creator.updated` from and to; Profiles: each link a `.plink`
    opening the profile, Edit links opening the creator sheet on its links
    alone (`#addCreatorBox.is-links`), Link history a fold with Restore;
    Creator page: the link and access code, Copy link, Preview), Payment
    (Creators List View: the payment details with Approve and Decline, the
    Bukku band, the payments; its tab counts details to review), Bookings
    (every campaign they were booked on, its step, opening the campaign) and
    Activity (`activity.campaigns` View: the record filed under their name);
    the rail's Next action (Review payment details), Record (campaigns,
    last shoot) and Totals (`creator_totals`, read once a visit and again
    after Read from Bukku; 2026-11-12): Billed to clients, each booking's
    client rate from Confirmed on in its client's billing currency, and Paid
    to creator, the paid bills of the bookings Agreed counts, so Agreed is
    Paid and Outstanding together, then Earlier payments, the paid bills no
    booking holds, drawn only where there is one (`earlier`,
    `2026-11-19-creator-totals-add-up.sql`), at `campaigns.pay` View alone,
    a line a currency, never added across. New creator is the one sheet left and opens the new
    creator's page.
  - Rate bands: Up to RM 300, RM 301 to 500, RM 501 to 800, Above RM 800, On
    quote. Inactive in its own band.
  - A platform filter.
  - The record cell counts and dates (`DONE_STATES` from `confirmed`,
    `submitted` included) and never names a campaign.
  - `nameKey()` trims, collapses whitespace and ignores case. The name is
    stored that way, and the duplicate is refused before any link is typed.
  - The word is Creators List, never "roster".
- A campaign's rates are in the client's currency (`mkt()`): for a client
  billed in S$ the Creators List's RM is turned at `fx_sgd` to the cent and
  the field reads S$, left empty while no rate is set; a creator made from
  such a campaign keeps the list's rate in RM (2026-10-22, CMP-1).
- Adding creators, its Undo and Remove are filed under the campaign
  (`campaign.offered`, `campaign.unoffered`); Remove asks nothing and
  offers Undo, which puts the same row back (2026-10-22, CMP-3, CMP-4).
- Add creators is a sheet (`#addOptionBox`, 2026-10-10; the user: "messy …
  no proper grouping"): the strip Creators List / New creator; a search by
  name or handle and a platform; the Creators List's fee bands (stood down
  left out) and Already in this campaign last, each its state; a tick a
  creator opening its client rate and platforms, prefilled from the list;
  the foot's count and sum of the rates, and one Add N creators inserting
  every tick at once (all or none), Undo where it happened. A creator
  withdrawn or replaced here (not goodwill) is offered from the same list:
  their one row (`unique (campaign_id, creator_id)`) moves back to Offered,
  its reason cleared, filed `campaign.reinstated` … offered again. Ticking a
  platform with no link grows the box into the field (`.pbox`), saved to the
  creator through `readProfile()`.
- A creator's profile links (`creator_profiles`) are saved only through
  `profiles_replace()`:
  - `creator_set_profiles` (the creator) and `creator_save_profiles` (Work).
  - `profile_of()` accepts only real profiles on the four platforms and
    rebuilds the link.
  - A profile another creator holds is refused.
  - A creator cannot empty their set.
  - Each change is filed twice (`creator_profile_changes` plus activity).
  - Link history offers Restore (`creator_restore_profiles`).
- Creator portal (`creator/`, `js/creator.js`):
  - Signs in with an eight-character code (`creators.access_code`, 31-character
    alphabet), carried in the link and kept in `localStorage`. Reset in the
    record. Typed, it is a box a character (`js/otp.js`, `data-otp-chars`
    alnum; the user, 2026-11-22), in capitals, a deletion emptying the last;
    pasted as printed, `7K2M-9PQR`, the dash is dropped and never sent. Its eighth character, typed or
    pasted, checks it with no press (`js/otp.js`'s Enter on a whole code, the page's one check; Forget this device empties the field; the same code is not sent
    again until it changes, nothing while an input method composes; Open
    stays). A wrong code is counted against the caller's address
    (`creator_code_try`, `link_tries` kind `creator`,
    `2026-10-27-creator-codes-counted.sql`): five within 15 minutes lock it
    out, the right code included, for 15 minutes, then an hour, then a day;
    a right code resets nothing; no count across addresses. `get_creator`,
    `creator_set_profiles`, `push_subscribe`, the creator branch of
    `share_link_preview` and every creator write (`creator_submit`,
    `creator_add_file`, `creator_remove_file`, `creator_rate`,
    `creator_may_upload`, `creator_post_save`; audit 2026-11-15) ask it; the page says `locked` as a link's lock
    is said (`W.lockedLine`).
  - `get_creator` sends the creator's own booking only.
    - Never the client's stage, commercial state, amount, other creators or
      the team's notes on the row.
    - It sends the open request's note (`change_note`) from the record,
      either side's and never one taken back (a team round from before the
      record reads `drop_reason`). "As noted below" is said only where a
      note is below.
    - Never `rate` or `currency`: the rate is the client's price with markup.
  - Uploads: `creator_can_deliver` at pending draft / changes / submitted;
    `creator_can_retract` shuts at submitted.
  - A file's kind falls back on its extension (`typeOf`, `kindOf`,
    `mediaKind()`).
  - Signed PUT via `sign-upload`, using `creator_may_upload` with a key built
    from the verified option. `creator_add_file` records only the address
    `sign-upload` made for that booking (`bad-file`), a name of 1 to 255
    (`bad-name`) and a kind of image, video or file (`bad-kind`;
    `2026-10-17-creator-files-held-to-their-folder.sql`).
  - Each signed upload is claimed first (`creator_upload_claim`, the
    service role's, after the type and size are checked): fifty files and
    25 GB a booking a Malaysian day (`creator_upload_counts`, RLS on, no
    policy, no grant), then `too_many` (429), said as the day's limit
    (`uploadMany`; security audit 2026-11-09).
  - Picked files are held on the device (`held`, `.filecard.is-held`, ×
    each) and upload one by one only on Submit or Update; each row is
    written after its file is stored. A failure keeps that file held and
    hands in nothing; every failure is named after the repaint.
  - A caption typed and not handed in is kept a booking in this tab's
    session (`adspace-creator-drafts:{code}`), through a booking switch, the
    language and a repaint; Submit and Forget this device clear it, and
    leaving with it asks first. Nothing but Submit sends it (audit F4,
    `tests/capdraft.js`).
  - Payment details are the page's own card, asked once from the first
    booking (Creator payment details, above), never on a booking.
  - The page is three tabs under the head (`#crTabs`, the view strip,
    `?tab=`, Bookings left out; 2026-11-10, the approved mockup): Bookings
    (the queue and the open booking, the red count of what waits on the
    creator), Payments (drawn once details are asked or a booking holds a
    payment: the Payment details card, then each booking from Confirmed on
    as one line, the campaign and its Job reference beside Paid {day} (the
    day of Bukku's payment voucher), Pending payment once posted or billed,
    else Not due, never an amount, a bill number or a currency (anyone with
    the link reads it; the user, 2026-11-12), and the working days payment takes, all from
    `creator_pay_form` `payments` and `days`, the creator's own alone;
    `2026-11-10-creator-page-payments.sql`) and Profile (the profile links
    with Edit links, and Contact: the WhatsApp and email held).
  - `creator_rate` takes 1 to 5 at completed and is never shown to the client.
  - Post and results (Scheduled, Posted; read-only at Completed): per
    placement, the post link (the platform's own host, `post_link_ok()`),
    its date, and views, engagements and impressions over the count period.
    `creator_post_save` writes them (`entered_by` creator, filed
    `campaign.results`; a link holding `"`, `'`, `<`, `>`, a backslash or a
    backtick refused `link`, `2026-10-17-post-links-plain.sql`); numbers are refused (`period`) until the team sets
    `measure_from`/`measure_to`, which only the console writes; until then
    the page says nothing about the period. The first link at Scheduled
    moves the booking to Posted.
  - The countdown is amber, then red once passed.
  - The page is a queue ordered by what is owed, with one booking open in
    `location.hash`. A lone booking has no queue and runs the page's width.
    The queue is a row of cards over the open booking (2026-11-25, the
    approved CreatorBooking board), scrolling sideways on a phone, the open
    one ringed in ink; the open booking's steps are discs on a line
    (`ADspaceIcons.journey` with `glyphs` and `days`: done the green tick,
    the step in hand outlined, each with its date under it where one is
    held), its facts two columns of glyph discs (an odd count's last fact
    taking the row, never alone on it), its brief a shaded box.
    Payments and Profile are two columns at 900 and over (Profile 1.618 to
    1), a lone card the pane's width; Payments' rows lead with the
    campaign's glyph tile.
  - A completed booking ranks with the ended ones, faded last, and the page
    opens on a running one; its card is its name and state, the rating while
    not given, and Booking details folded shut with no steps
    (`.booking-fold`; the user, 2026-10-14: "subsequent new bookings could
    be the main focus").
  - The open booking (2026-10-08): its six steps by name
    (`ADspaceIcons.journey`; Submitted and Reviewing are Review); what is
    owed (Next up: Submit your draft, or the revision, its countdown, the
    change note, the files and one large Add photos or videos area, the
    caption opening two lines) above the facts, else where the booking
    stands as one line in ink there (`.cx-status`), so after Submit it is read
    without scrolling; the facts carry their glyphs, the place Directions
    (Google Maps), the contact WhatsApp and Call.
  - The Draft step's `?` hint opens by itself three times, then retires
    (`hint()`, `bumpHint()`).
  - Sign out is named, and hidden until there is a session.
- Creators selection page (`creators/`, `js/creators.js`):
  - Built from the mockup the user approved on 2026-11-25: the head (the
    client's mark, the campaign over its client, Choose by with its weekday
    `22 Sept (Tue)` and Creators n of N at the right, rows on a phone), the
    brief as one shaded line (never folded), the view strip All, Selected,
    Backup with counts, a shaded card a creator (two across beside the cart
    at a desk, one on a phone) and the cart. No profile picture and no
    follower count: neither is held.
  - When the slots fill, the unpicked leave. A tick past the slots is
    refused on the card pressed (`.cs-msg`), never greyed silently.
  - The fee is read under it with the deliverable it buys and its
    placements (`per video · rednote, Instagram`, `platsOf()`).
  - Backups only with `campaigns.backups_open` (`save_selection` refuses
    otherwise).
  - A placement line on each row (`platsOf()`).
  - The campaign room (2026-10-08): under the name card, where it stands (n
    of N posted, a segment a booking in its state's dot, a legend, the next
    shoot); a booking waiting on the client (a draft at Reviewing) leads the
    page in its own card (`#needBox`: Waiting for your approval, the draft and
    the decision) and leaves the list below while it waits; each booking is
    numbered, never a photo (the user, 2026-10-07), the numbers carrying on
    through Available creators, with its six steps by name (a Submitted draft
    is the client's Draft step; none once Completed, 2026-10-10); the results
    lead with one figure (views, else impressions), then impressions,
    engagements, engagement rate and per engagement, and the top post where
    more than one is live.
  - Each live post on a booking reads as the Top post does (`postRows`,
    `.cx-post-item`; the user, 2026-10-10): the booking's picture, the
    platform and its day, views (else impressions) and engagements as glyphs
    named for a screen reader, Measured {day}, and View post on {platform}
    (`.postlink`; 查看小红书笔记 in Chinese) at the row's right edge at a
    desk, the card's full width on a phone. Never a results table. The
    campaign's one live post keeps its figures in the results card alone.
    The card's Posted and Posting on facts leave once a post row says them;
    the approval line leaves once the post is out.
  - A draft is decided on the card (`draftPreview`); in `#needBox` at a
    desk the pair stand 220px each at the card's right edge, Approve last,
    and Open the draft at its own width (2026-10-22, CP-17); a phone keeps
    equal halves.
  - `review_draft` rules on a draft at Reviewing alone, the booking held
    while it does (a page left open from before a request for changes
    cannot approve the unrevised draft; audit 2026-10-29).
  - `review_draft` logs under the typed name. `get_campaign` sends the last
    review.
- Client-side decisions write an activity row under the typed name:
  `submit_review`, `confirm_selection_with`, `creator_submit`, `creator_rate`,
  `portal_withdraw`. `save_selection` does not (it autosaves).

- A write to a campaign goes through `writeCamp(c, patch)`: held to the
  copy's `updated_at`, its new stamp taken back; refused, `staleCamp` reads
  the campaign again and says `ADspaceWords.line.stale`. Edit sends only
  the fields that moved. The Creators List and the campaigns list read
  every row through `ADspaceAPI.readPages` (review 2026-11-24,
  `tests/editstamps.js`).

## Components

Moved from DESIGN.md §4 on 2026-11-22.

| Need | Component |
|---|---|
| Every creator's payment work (Creators, Payments) | `#payView` (`js/campaigns.js`): the section's strip, its own bar (`#cpqBar`: search, Client, Campaign and Currency pills, the count, Read from Bukku and the one blue Create n bills), then an `ADspaceGroup` card a group in order (Details to review, Ready to bill, Draft in Bukku, Awaiting payment with its late count as a red `.tab-n`, Paid with its period as a small select at its head's right); a `.cpq-row` the creator at 500 with the Job reference in the token face over the bill number, campaign and client in 12.5 mute, the amount (tabular, 500) over Pay by, its days late in red or Paid {day} at the right, the act (`.btn-sm`: Review, Create bill, Link to Bukku, Open in Bukku) in a 128px track last; on a narrow pane the act takes the row under them at its width. Review is a `.formsheet` of Billing, Payment and Contact read as `.ovfacts`, a changed fact its grey Changed chip with Before under it, Cancel, red Decline and blue Approve in the foot |
| A creator's payments (the creator page's Payment pane) | After the details, the Bukku band (`.bk-band`, Send to Bukku), then Payments (`#cpayJobs`, Read from Bukku a `.btn-sm` at its heading's right): a booking a `.cpay-job` row, its Job reference in the token face over its campaign and earlier job ID, its bill's state (`.chip-state`: Paid, Processing, Not billed with Pay by, Not due) over the bill's number and amount at the right, its fee (Fee RM …, else Fee not set, at Creator payments View) after the campaign, Create bill (`.btn-sm`) under the state where a bill can be made (its question asks the amount), the pen (the fee and the earlier job ID) last; Create n bills beside Read from Bukku once two are ready, a `.msg.warn` line where no Bukku account is chosen; Earlier payments the bills matching no booking, under their heading; Read from Bukku {day, time} a mute line at the foot |
| A creator's payment details on the Creators List | After the name, never a column (the user, 2026-11-12): approved a green 8px dot alone (`.cr-paydot`, `--dot-ok`, 8px after the name, `role="img"` named Payment details approved, its title on hover), the one dot that stands without its word, since nearly every row holds it and none submitted shows nothing; To review and Declined their `.chip-state` with its word |
| A creator's payment details (the creator's page) | `.panel.crpay` under the head: the record head's shape (`.rec-id-solo`), a 16/600 title over its standing (`.chip-state` and its parts, each held whole, `.crpay-part`), the act at the right (blue Submit details while none is held or one was declined, else tonal Change details), the details paid to as `.ovfacts` under a hairline (104px labels on a phone), numbers by their last four; its sheet a `.formsheet` of three `.fsec`s (Billing, Payment, Contact) and the confirmation tick, a choice that changes the fields under it redrawing them with what was typed kept |
| A creator offered for selection (/creators/) | `.cs-card`: a `--sunk` card, no outline; the number and the name (Replacement or New a grey `.chip`), the round tick at the top right (`.cs-tick`: a ring, selected a blue disc with a white tick, the card then white with a 1.5px `--action` edge), the profiles as `.plink`s with the platform's mark and the leaving mark, a hairline, the fee 17/600 over its unit mute, Mark as backup (`.cs-backup`, `.btn-sm` with the bookmark; marked, Marked as backup on the ink fill with the bookmark filled, a press again unmarks) |
| The client's selection, totalled (/creators/) | The cart, as Build quote's Summary: at a desk `.sumcard.cs-cart` sticky under the bar in the 1.618 : 1 split (Your selection with its count as a `.tab-n`, each selected name and fee, the backups one mute line, Subtotal, SST at the campaign's rate through `js/money.js`, Total 17/600, Submit selection blue at the card's width); on a phone `.cs-bar` fixed at the foot over the safe area (n of N selected and the total over the backups and incl. SST, then View selection with its count and Submit selection as equal halves at the control's height, nothing in the bar setting its own), View selection carrying the cart into its sheet |
| A booking's steps (client pages) | `.cx-journey` (`ADspaceIcons.journey`): a hairline a step with its name under it in 12px, the done steps in the mute ink, the one in hand amber with its name in ink, as Apple tracks an order; never bare bars, never large ringed marks (the user, 2026-10-08) |
| Where a campaign stands (client page) | `.cx-standing` under the name card: n of N posted, a 6px track a booking in its state's dot colour, a legend, the next shoot |
| What the client owes (client page) | `.cx-needs`: the booking's own card above the rest, led by the amber dot and Waiting for your approval, the booking leaving the list while it waits |

- The Creators List's tiles (2026-11-22, the Bukku structure, decision 5):
  `#rosterTiles` over the bands, as Clients has them: Active creators,
  Details to review (the oldest submitted), and at Creator payments Ready
  to bill (the fees, those not set in the foot) and Awaiting payment (the
  bills late in red), from `creator_payments_queue`'s one read; hidden
  while a creator is open.
- A creator's payment row (`.cpay-job`) is the phone row (`.prow`,
  2026-11-22, decision 3): the reference over its campaign, the state, the
  end (a date, a bill, an amount, each part whole) and the ⋯ in their
  slots, the ⋯'s slot kept on every row; on a phone the end takes the room
  the state and the ⋯ leave (`contain: inline-size`), so a long campaign
  name never runs under it (`tests/supbills.js`).
