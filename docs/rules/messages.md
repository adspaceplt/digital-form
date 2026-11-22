<!-- triggers: js/whatsapp.js js/mailtpl.js supabase/functions/wa-send supabase/functions/wa-hook supabase/functions/_shared/mail.ts -->
# Messages: WhatsApp and Email (`js/whatsapp.js`, `?s=whatsapp`, `wa-send`, `wa-hook`, `2026-10-09-whatsapp.sql`, `2026-10-10-whatsapp-section.sql`, `2026-10-10-whatsapp-approval-reminder.sql`, `2026-11-04-email-log.sql`, `docs/WHATSAPP-SETUP.md`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- The section reads Messages on the rail, the tab bar, its heading and the
  Team panel (the user, 2026-11-04: "the email and whatsapp log sits
  together in one section under different tabs"; its key, address, parts
  and Settings' WhatsApp group stay `whatsapp`): two tabs (`#msgViews`,
  the view strip, a sideways swipe; `tab=email`, WhatsApp left out), each
  its own bar and month. Email (`#emlPane`) lists every email the portal
  sent in the Malaysian month, newest first, from the logs its senders keep
  (`mail_log(p_month)`, Messages at View first, each row at its own
  record's access: supplier emails at Suppliers View, a quotation, Letter
  of Offer or client letter at its kind's part (`client_email_may`) on a
  client in scope, overdue reminders at Clients: Billing View, a
  quotation's signing code at Clients: Quotations View, never the code,
  read Code sent, Signed or Expired, Requested by Client), the month's sent, delivered, opened and
  not delivered (red, where any) in the line under the section's name, filtered by Type and Status; a row is one button
  opening the email as sent (`#emlSheet`: From, To, Copy, the client or
  supplier opening its record, Reference, Sent by, Status, each step's
  time, a bounce's reason, the message). Every email the portal sends is
  in it (the user, 2026-11-17: "All outgoing WhatsApp messages and emails
  should be logged inside"; `2026-11-17-every-email-in-messages.sql`): a
  sender with no log of its own files each send once Resend answers
  (`system_emails`, RLS on, no policy, no grant; `system_email_file` and
  `_shared/mail.ts` `fileSent`, the service role's): hiring-mail's
  invitation, confirmation, time change, outcome and document at the candidate's own
  access (`hiring_role`), its document code (Code, Requested by Candidate,
  its words never kept), and invite-member's invitations, a colleague's at
  Team View and a client contact's at Clients: Contacts View on a client in
  scope (a sign-in link's words never kept); a new sender files the same
  way. Supabase's own sign-in codes are not the portal's to log.
- The send switches (`2026-11-21-send-switches.sql`; the user, 2026-11-21,
  on a mockup: "if its disabled then it wouldnt show... misunderstanding
  that the function is on", "why not just make it disabled"). Three tiers,
  top to bottom: Settings, Portal: Email and WhatsApp (`email_on`,
  `whatsapp_on`), off sending nothing below; Settings, Messages: Send by
  email (`client_email_on`: every email a colleague sends by hand, template
  or not: a quotation, a Letter of Offer, a client letter, an overdue
  reminder, an invoice email, a supplier's emails, New email to a client or
  a supplier, Send again) and Send on WhatsApp (`client_wa_on`, seeded On:
  every WhatsApp sent by hand, the composer, a quotation, a letter, a
  report, a feedback request, a reminder, Send quotation), Automatic emails
  and Automatic WhatsApp beside them for what the portal sends by itself
  (a creator's payment emails and every candidate email, `hiring_mail_gate`;
  a step that sends one goes ahead while it is off, warning first; Automatic
  WhatsApp's booking confirmation is warned on an open campaign's Client
  link, `#campWaOff`, through `ADspaceAdmin.autoOff`);
  then the group's Send email and Send WhatsApp (who may send by hand). A
  Messages switch under a portal switch that is off stands still and reads
  Off for the whole portal. A send act the group may not take is hidden; one
  Settings has switched off stays drawn, disabled, its reason said at a
  press, a hover or the keyboard's focus (`data-gate`, `#gateWhy`,
  `ADspaceAdmin.gateState`), a sheet's own Send alike. A sign-in code, an
  invitation and a verification code are never held by any switch.
- New email (`#emlNew` on the Email bar, Messages at Work;
  `2026-11-04-new-email.sql` and its SQL Editor part; the user, 2026-11-04):
  `#nemSheet` asks For (Client, Supplier, Other as a segment): a client's
  To a select of its own live contacts holding an email and, at Clients:
  Billing View alone, its finance email (`email_recipients`,
  `email_client_options`), Copy a tick each (five at
  most); a supplier's its email and finance email; Other an address typed
  for To and one for Copy (`ADspaceWords.emailOk`). Template: Custom
  message, else a saved one for that audience (Other: both), filling the
  subject and message; {contact name}, {company name}, {client name},
  {supplier name} and {sender name} are filled by `email_new_begin`
  ({company name} the registered name at Billing View alone, else the
  brand; Send by email the same). One
  file optional (PDF, picture, Word, Excel, PowerPoint, CSV; 10 MB). Send
  asks first, then `supplier-mail` `manual` checks the file (a PDF that is
  a PDF), files it (`email_new_begin`: the record's own addresses alone,
  `bad-recipient`, `bad-copy`, `bad-email`, one key a sheet `again` with
  its email's status, read Not confirmed where it never went, a
  hundred a colleague a day `too-many`), sends it in the branded layout from the clients' sender (a supplier's from
  the suppliers'), and closes it (`email_new_done`, filed `email.sent` under
  Messages by the recipient's name and the number of copies, never an
  address; Send by email's `client_email_done`, `supplier_email_done` and
  `invoice_email_done` alike; 2026-11-04). One to or copying a finance
  email is marked (`team_emails.finance`) and read on the client and in the
  log at Clients: Billing View alone (`2026-11-04-emails-keep-billing-and-history.sql`). `team_emails` (no foreign key, RLS on, no policy, no grant)
  joins the Email log (a row's subject over its file), Resend's word and
  `mail_sweep`. Settings, Messages: Email templates, New email under Clients
  or Suppliers (`ADspaceMailTpl`, `team.settings`, a supplier's at Suppliers
  Full Access too, `email_template_may`; `email_template_save` with
  `taken`, `email_template_delete` in the row's ⋯, filed under Email
  templates). A client's audience asks Clients: Contacts at View too
  (its addresses are that part's): without it no client is offered, its
  email is refused (`denied`) and its rows leave the log. A client record's
  Contacts pane lists the emails written to it under Emails
  (`team_emails_of`, the log's own row and sheet, New email beside it) and
  a contact's ⋯ Send email opens it on that contact; a supplier record's
  Emails list them beside its own (`supplier_emails_of`). Send again on an
  email in the log opens it filled as it went (its file attached afresh);
  an address the record no longer lists is not chosen in its place
  (Choose an address).
  Send again (`2026-11-18-send-again.sql`; the user, 2026-11-18: "so failed
  email could be resent"): an email in the log that did not arrive (Not
  sent, Bounced, Not confirmed) goes again through its own sender, drawn
  as the first was, at Messages Work with Send email on: a creator email
  queued again in its first words as the colleague's
  (`creator_email_again`, Creators: Creators at Work; `already`,
  `not-failed`, `gone`), never held by Automatic emails off; a hiring email
  by hiring-mail for the record it was about (`system_emails.ref_id`), an
  invitation by invite-member, each with `againOf`, filed on the email it
  sends again (`again_of`). Asked first (Send again?), said in place (Sent
  again.), offered once. A document's or a reminder's email is sent again
  from its record, where its PDF is drawn (`tests/sendagain.js`).
  An email's addresses and words are cleared 12 months on, its subject,
  status and times kept (`mail_retention`, pg_cron `mail-retention`, the
  2nd at 03:45 MYT; client, supplier, invoice and New emails alike), read
  as Address deleted; a signing code's address and details 30 days after an
  unused code expired or a year after its use; an address an email filed
  in the Activity record before 2026-11-04 a year on (a deleted address),
  the senders' own lines alone (emailed to …), never a contact's or a
  supplier's change of email, which the record keeps its three years.
  Resend's email.failed reads Failed, a status that arrives before its
  email is closed is answered 503 for ten minutes, and one the database
  could not take 500, so Resend asks again. The SQL Editor part also drops the 10- and
  11-argument invoice begin wrappers nothing calls since bukku-sync v26.
- Messages go through the WhatsApp Business Platform (Cloud API), each with a
  template Meta approved (the user, 2026-10-09: report to client, team
  reminders, creator updates, a feedback request sent by hand). Phase 1
  (2026-10-10): the section, the composer, the delivery status; no inbox, no
  message to a colleague but the queued reminders, nothing sent to an AI
  service.
- A section of its own, `whatsapp`, the last of the Work group (the user,
  2026-10-10: "whatsapp tab should go to the last inside work"): View
  reads the messages, Work (Manage on the panel) sends, Manage (Full Access)
  sets the templates. Its parts `whatsapp.report`, `whatsapp.feedback`,
  `whatsapp.booking`, `whatsapp.approval` (2026-10-10) and
  `whatsapp.documents` (Quotations and letters, 2026-10-14) follow it or are
  shut (No Access), nothing between
  (`VIEW_PARTS`); they replaced `reports.whatsapp`, `clients.whatsapp` and
  `campaigns.whatsapp` (a shut one moved across, the old keys taken off). A
  send asks the section and its purpose's part at Work and the record's own
  section at View (Reports, Clients, Creators), a plain message a
  contact's Clients: Contacts or a creator's Creators List at View, an
  approval reminder Content Review: Content sets or Creators:
  Campaigns at View and the record it names at its own, a quotation
  Clients: Services at View, a Letter of Offer Clients: Documents at View
  (`wa_may_send`, `ADspaceWhatsApp.may`); at No Access no record offers
  WhatsApp. Groups started once: Admin Full Access, Clients Work or above
  Work, Clients View View, else none.
- Messages (the landing view, `wa_messages(p_month)`, client scope; a
  colleague recipient's number reads as its last four digits without Team
  View, security audit 2026-11-09): one
  table of the chosen month's messages (Malaysia time, read from
  `ADspaceClock`, `9 Oct, 2:05pm`), never a card naming the month again,
  newest first (2026-10-22, WA-2, WA-3), a row who it
  went to (name; client, Creator or Colleague; the number as
  `ADspaceCard.phone` writes it), what it was (Report, Feedback request,
  Booking, Reminder, Message over the template, which gives way, and its
  category, read whole; on a phone the meta line leads with what was sent,
  the number leaving first; WA-4), who sent
  it (Automatic for the queue) and the status over when: Queued, Sending,
  Sent, Delivered, Read, Not confirmed (check the chat before sending again), or Failed with the reason in the team's words
  (`REASON`, by Meta's code) and Open contacts (a client contact's
  Account) or Open creator (the Creators List) where the reader may
  (2026-10-27, WA-10). An empty month reads No messages. alone, New
  message being the bar's (WA-8). The line under the section's name
  reads the month's templates sent by category (utility, marketing;
  authentication where any; a message Meta failed left out), a figure at
  nought left out and the month's total the bar's count alone (2026-11-13);
  a template reads as words (`tplName`: Quote ready), its Meta name on
  hover. The bar: search
  (name, client, template, a number as typed), Month (a view, the last
  twelve), Type and Status behind Filters, the count, New message (Work).
- At Full Access the queue joins that line (queued, sending, failed and
  not confirmed in the last 7 days, the last two in red, each only where
  it holds any; `wa_messages` `queue`). The
  templates are Settings, Messages: WhatsApp templates (`#waTplSheet`,
  `ADspaceWhatsApp.manage`; 2026-10-29: the section's Templates tab gone,
  an older `tab=templates` reads the messages): one template a purpose (`wa_templates`: `report`,
  `feedback`, `reminder`, `creator`, `approval`; name, language, category, how many body
  variables, On): Edit chooses from Meta's approved list read through
  `wa-send` (never typed; the report's needs a Document header and no other
  takes one; a link button's variable refused only for the team reminders, which the portal sends by itself (`NO_BUTTON`);
  only templates the purpose can take are offered, 2026-10-20, WA-2; one
  whose link button's fixed part holds a variable typed by hand, `%7B%7B1%7D%7D`,
  is never offered, its row and the composer name it and Send rests,
  2026-10-22, said under its name in a warn line), the sheet one table
  with no fold over it and the pen alone (revamp C, 2026-11-04), each row's
  switch (`.switch`) turns it on or off at the press (one with no template
  asks for one first); `wa_template_set`, filed `wa.template` under
  WhatsApp from and to. A purpose that is Off sends nothing and its record
  button is not drawn. The account menu holds no WhatsApp item.
- The composer (`ADspaceWhatsApp.compose`, `#waCompose`), one sheet every
  record shares: To (`wa_recipients`: client contacts named with their
  client, active creators; never a colleague; one with no number listed
  last as · No number), the number as it will be
  sent, else why not (a username alone cannot be messaged), with Open
  contacts on the client's Account where Clients: Contacts is readable
  (2026-10-22, WA-5); Template
  (Meta's approved ones the portal can fill: a Document header, a text
  header with one variable, body variables positional or named, one link
  button variable); each variable prefilled from the record (the greeting
  by `contact_greeting`, then the client or the report's brand, or a
  creator's campaign; the report; a named one by its name), a typed one
  kept; the link button the record's own, shown and never typed: `wa-send`
  fills it from `wa_compose_prepare` alone (a creator's `code`; an approval
  reminder's `link`, past the button's fixed base) and refuses `wa-no-link`
  where the record holds none (2026-10-19); a numbered one named for what fills it
  (Greeting, Client, Campaign, Report, Reference, What waits, Link); a Report select only for a Document
  header, the recipient's client's published reports newest first, its file
  the kept PDF the client portal hands over (`ADspaceReports.keptPdf`), which
  `wa-send` reads itself as the caller through `sign-download`, never the
  page's bytes, a quotation's or letter's refused unless it is a PDF whose
  title names the record's own reference (`_shared/pdfref.ts`, the one
  reading, supplier-mail's too; 2026-10-22, LEAN-1) (each stream inflated with only
  its one closing line break cut, the file's streams inflating to 20 MB
  at most, past which it reads as not naming it; `bad-file`; audit S3,
  2026-10-15;
  the letter's PDF titled `Letter of Offer {number}`); the
  message previewed as it will read. Send asks (`ADspaceConfirm`, naming
  the recipient, the number and the category), then `wa-send` `compose`
  asks `wa_compose_prepare` as the colleague (the number and the record are
  the database's), reads the template again from Meta, files it as Sending
  first (`wa_send_begin`, below), sends and closes it (`wa_send_done`, the
  sender's own row: Sent, Not confirmed or Failed; `wa.sent`, WhatsApp in
  the Activity record; a booking's under
  its campaign as `{creator} · Booking sent on WhatsApp`). Purpose: a
  report attached is `report`; else the record's (`feedback`, `creator`),
  else `message`. The record buttons stay where they were and open it
  prefilled: Send on WhatsApp beside Mark as sent (then marked as sent
  today), Request feedback in a client's ⋯, Resend booking in a
  booked creator's ⋯ at Confirmed and Pending visit alone (the booking goes
  out by itself on confirming; the user, 2026-10-11).
- A quotation and a Letter of Offer (`quotation`, `offer`,
  `2026-10-14-whatsapp-documents.sql`, the purposes added by
  `2026-10-14-whatsapp-document-purposes.sql` in the SQL Editor; the user,
  2026-10-14: the team decides which to send once a client proceeds): Send
  on WhatsApp in a quotation's ⋯ (not removed, not Cancelled) and a
  Letter of Offer's ⋯ on the client's Documents (not voided or replaced;
  `wa_compose_prepare` refuses either `void`), each drawn once its template is on; the composer takes the
  record fixed (`o.doc`: `#waDocOne`, a readfield, never a select of one),
  its PDF drawn in the browser as Download draws it and sent as the
  Document header; variables the greeting, the client, the reference; to a
  client contact of that client alone; filed as Quotation / Letter of Offer
  sent on WhatsApp. Sent by hand only: the one automatic send to a client
  or creator is a creator's booking confirmed.
- Sent recently (`2026-10-14-whatsapp-sent-recently.sql`; the user,
  2026-10-14: "so no duplicate would be repeated sent"): before a send the
  composer asks `wa_sent_recently(p_to_kind, p_to, p_purpose, p_ref,
  p_template)` for the newest message not failed to that recipient for that
  purpose and record (a feedback request its client, a plain message its
  template) within `wa_repeat_hours` (24; Settings, Messages: Sent again; 0
  to 168, 0 asks nothing); found, Send asks in warn instead (Sent recently:
  to whom, by whom or automatically, when and how long ago; Send again),
  and `wa-send` refuses `recent` unless that question was answered
  (`again`), so a send made meanwhile asks too. A queued booking counts.
  The check and the filing are one step (`wa_send_begin`, 2026-10-19): a
  lock on the recipient, purpose and record, then `sending` while the same
  message is on its way (even with `again`), then `recent`, then the row
  filed as Sending before Meta is asked, so two presses send once. A
  feedback request or a plain message is Sent recently for any message of
  the same template to the same recipient, whatever purpose it was filed
  under (`2026-10-20-whatsapp-feedback-sent-once.sql`, WA-1).
- Variables of the queued ones in order: reminder (first name, title,
  message), creator (first name, campaign; its link button's variable the
  creator's code, `wa_outbox.button`); a template takes the first n.
- The approval reminder (`approval`, 2026-10-10; the user: "yes" to the
  chaser, sent by hand, never automatic): to a client contact, `p_ref` a
  published set of their client or a booking at Reviewing on a campaign of
  theirs (`not-found`, `not-waiting`), filed against it (`ref_kind` `set` /
  `option`) as "Approval reminder sent on WhatsApp to …"; variables in order
  the greeting, the client, what waits; the link to approve it rides a
  link button (`https://digital.adspace.me/{{1}}`, filled `review/?k=…` or
  `creators/?k=…`), else a fourth body variable. Its purpose
  is added to the check in `2026-10-10-whatsapp-approval-purpose.sql`, run
  in the SQL Editor (the connector stops on the check's replacement).
- Delivery (`wa-hook`, Verify JWT off): Meta's verification answered only
  with `WHATSAPP_VERIFY_TOKEN`; a POST believed only with its
  `X-Hub-Signature-256` over the raw body keyed by `META_APP_SECRET`; each
  status recorded by `wa_status_record` (the service role's alone) against
  `wa_outbox.wa_id`: `delivered_at`, `read_at`, `failed_at` with
  `fail_code` / `fail_title`, Meta's pricing category; a delivered or read
  message never turns failed; a status the database could not take is
  answered 500 after the rest are recorded, so Meta sends it again
  (2026-10-22, WA-1). Messages sent in and coexistence echoes are
  not read.
- A number is `wa_number`'s international form, read as the team types it
  (`2026-10-09-whatsapp-numbers-resend.sql`): a leading 0 is Malaysia (60
  for the 0), any other eight digits Singapore (65), nine or ten starting 1
  a Malaysian mobile without its 0 (60), else as typed with its country
  code; the console's wa.me links read them alike; a `@username` cannot be
  messaged (`no-number`). A client's main contact's WhatsApp number, else
  its phone; a colleague's mobile; a creator's `creators.whatsapp` (the
  Creators List sheet).
- A new template is named `{what it is about}_{what happened}`, the
  subject spelled whole (`quotation_`, never `quote_`;
  `prospect_contact_made`); the names standing on 2026-11-11 stay, since
  Meta cannot rename one and a new one starts its analytics afresh (the
  user, 2026-11-11: "lets not change name … in the future please try to
  streamline"). A template button never links to wa.me (Meta refuses it):
  a colleague is reached through their namecard's short link.
- Introduce representative (`representative`, `2026-11-11-representative-on-whatsapp.sql`,
  its SQL Editor part; the user, 2026-11-11): a lead's ⋯ (Lead, Contacted,
  Proposal sent, its Sales by set, Messages at Work and Clients: Leads at
  View, the purpose's template on) opens the composer on its contacts; the
  same template chosen in New message for a contact is sent as it. Its
  variables are the greeting, the brand and the Sales by colleague; its
  link button the colleague's namecard short link (`wa_compose_prepare`
  `rep`, `code`; `not-lead`, `no-sales-by`, `no-card`, `no-contact` for a
  prospect marked Do not contact), held as Sent
  recently by its client. The template is Utility: it states a fact about
  the lead's own enquiry, never asks them to call or buy.
- `wa-send` answers `report` and `feedback` with bad-request (2026-10-19). A refusal is one
  line in the team's words (`SAID` in js/whatsapp.js), never Meta's.
- Queued by trigger, never failing the write: a reminder in a colleague's
  bell (`tasks.empty`, `outstation`, `perf.remind`, `perf.reflect`,
  `health.remind`; `ops_notifications_wa`) and a creator's booking
  confirmed, with their code for the link button (`campaign_options_wa`,
  `wa_enqueue`; `2026-10-09-whatsapp-creator-link.sql`; changes requested
  and cleared to post stay on the creator's page and push) go to
  `wa_outbox` with their template's category; `wa_kick` (pg_net) wakes
  `wa-send`, which claims with the service role (`wa_claim`, `wa_done`;
  three tries of Meta's own refusal, then Failed), and pg_cron
  `outbox-drain` wakes it and `push-send` every five minutes while their
  queue holds something. A send whose answer never came (a dropped
  connection, a timeout, Meta's 5xx, a row cut off at Sending) is Not
  confirmed (`unknown`, filed `unknown:`), never sent again by itself, and
  counts as Sent recently (2026-10-17); a request that never left (DNS,
  connect, TLS) is filed `not sent:` and queued again with its try given back
  (`2026-10-18-whatsapp-outage-spends-no-try.sql`; Meta's throughput limit
  130429 filed the same way), and ends that drain
  (claimed again at once, a short outage spent all three tries). A message
  still queued 48 hours after it was queued is Failed by `wa_expire`
  (`expired:`, read "Not sent within 48 hours"; `wa_claim` and pg_cron
  `wa-expire` hourly), so Sent recently lets it be sent again and
  `privacy_retention` clears it in its time. The queue is
  claimed one row at a time (`wa_claim` gives one, five at most) and no
  send starts after 90 seconds, so a claimed row is never left at Sending. The queue and its tables are
  closed to every page.
- Secrets: `WHATSAPP_PHONE_ID`, `WHATSAPP_WABA_ID` (the templates),
  `WHATSAPP_TOKEN` (else `META_SYSTEM_TOKEN`, the user's choice, 2026-10-09:
  one system user holds both), `META_APP_SECRET` (`appsecret_proof` on every
  call, as `meta-import`; `wa-hook`'s signature), `WHATSAPP_VERIFY_TOKEN`
  (`wa-hook`), `META_GRAPH_VERSION`; Verify JWT off on both (pg_net and Meta
  call with no session).
- A wake of `wa-send`'s `drain` or of `push-send` carries the database's
  wake secret (`app_secrets` `wake_secret`, made once, never shown) as
  `x-adspace-wake`, which each function asks of `wake_secret_ok` (the
  service role's alone) before touching a queue, else 401; `wa_kick` and
  `push_kick` send it, once a transaction, so a statement queueing forty
  rows wakes each sender once (`2026-10-19-wake-calls-carry-a-secret.sql`).
- Every email goes with a plain-text copy beside its HTML, and the sending
  domain (`sc.adspace.me`) has Resend's click tracking off: an email of HTML
  alone, or links rewritten through a tracker, reads to Gmail as bulk mail
  (2026-11-18; `tests/mailfn.js`). Open tracking stays on for the Email
  log's Opened.
