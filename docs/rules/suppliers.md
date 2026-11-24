<!-- triggers: js/suppliers.js js/supplierform.js supplier/ supabase/functions/supplier-mail -->
# Suppliers (`js/suppliers.js`, `js/supplierform.js`, `?s=suppliers`; `supplier/`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- A section of its own (`suppliers`, View / Work / Manage; the user,
  2026-10-18: "own section"), in the Partners group after Creators
  (`2026-10-18-suppliers.sql`, `2026-10-18-suppliers-own-section.sql`;
  the user: the Jotform supplier sign-up "via portal and data sync into it
  similar as client billing", "invite only, with create link and set the
  supplier id before sending", "nric only for individuals"); `supplier=`
  opens one. `suppliers` and `supplier_forms` have RLS on, no policy, no
  grant.
- New supplier asks the Supplier ID alone (the next AS number offered at
  the width in use, unique, `code-taken`; the user: "i wont know the
  company name first"), makes it Pending and its link
  (`/supplier/?k=`, open `details_form_days`; Copy link, Preview,
  the ⋯ Reset link and Close link, each asked; `supplier_link_close`
  ends the open form now, filed, `2026-10-18-supplier-link-closed.sql`). Until its form names it a supplier reads its
  Supplier ID, Waiting for their details, until its form comes back:
  then Details received, the answers read in place under the form before
  Use details; a supplier holding no details reads No details yet., never
  groups of Not set (2026-10-20, SUP-1 to SUP-3).
- The supplier's page (`supplier_form_read`, `supplier_form_submit`, anon),
  in steps since 2026-11-25 (Billing details, Person in charge, Payment
  details, Authorisation; then the received page, no contact; DESIGN.md §4), each step
  leads For ADspace · Supplier ID, Enter moving to the next field and
  submitting from the last alone (2026-10-20, SPF-2, SPF-3), a failed
  send naming ADspace, never an account manager (`W.notSentAdspace`,
  2026-10-27, SPF-6),
  reads the Supplier ID (and the name once held) and checks as the Jotform
  form did: Company or Individual, NRIC (XXXXXX-XX-XXXX) for an individual
  alone, a company's 12-digit BRN, TIN, SST no. (AXX-XXXX-XXXXXXXX), Office
  / mobile a Malaysian or Singapore number and Mobile / WhatsApp a mobile
  (`supplier_number_ok`, the page alike), the payment term (NET 7, 14, 30,
  45, 60, subject to approval), MYR or SGD, the bank from its list, the
  authorisation ticked; the team at Suppliers Work is told (kind
  `supplier.details`, opening the supplier). The answers never write the
  supplier: Use details fills its sheet and Save (`supplier_save`) takes
  them in. A move of status (Approve, Set inactive) ends every open link of
  the supplier, filed with the move. An Active supplier whose details change
  is sent an update link (`supplier_forms.purpose`
  `update`, `2026-10-20-supplier-update-link.sql`) or edited by hand: the
  form opens on the details held but the NRIC and the bank details, which
  it never reads and which, left blank, keep what is held; the record leads
  with Details update, each change from and to (the bank as Changed), and
  Use changes, held for a colleague at `suppliers.pay` where the bank
  changed. An Active supplier holds one Details update form section under
  Payment details in every state (Not sent, Sent and open until, Link
  ended, taken in), its acts in its own head (Create link; open, the link
  with Copy link and Preview, the ⋯ Reset link and Close link). The
  record's ⋯ holds Edit, Set inactive or Set active, and Delete alone:
  Issue document (its ⋯ Add existing document) heads Documents, Send email
  heads Emails (2026-10-20, the user: six items read as too many). A new payee, bank or account
  on an Active supplier, by link or by hand, puts it back to Pending until
  approved again (`repending`), and an approval names who approved, never
  a system account. The record is its head card over a strip (`#supTabs`,
  `tab=` pushed, Overview left out; SUP-4, 2026-10-22): Overview (a form
  waiting to be taken in first, then Client, Billing details, Person in
  charge), Payment (Payment details, the Details update form, Bukku; once
  linked the Bukku band leads it, `docs/rules/bukku.md`),
  Documents, Emails; a pane with nothing in it is not drawn.
- Approve (`supplier_set_status`, a name, the details and the bank account
  whole, `incomplete`; under the record's head at its own width, `.sup-go`,
  2026-10-27, SUP-10) makes it Active; Set inactive / Set active in the
  ⋯, Delete at Manage with the name (else the Supplier ID) typed back
  (letters keep their words). The NRIC and the bank details are sent and
  saved only at `suppliers.pay` (granted), filed by name, never by value.
- A supplier's document is the Documents family `supplier`,
  `documents.supplier_id`, issued to an Active supplier alone, from its
  record (Issue document) or the Register (2026-10-20, DOC-3), listed on the supplier and under Supplier Letters
  (`register_may('supplier', …)` answers the Suppliers section); a reissue
  keeps the supplier. The one offered is the Supplier Service Agreement
  (`supplier_sca`, `2026-10-18-supplier-service-agreement.sql`; the user,
  2026-10-18; Letter to Supplier, `ASL/{Supplier ID}/{YYMMDD}{NN}`, no
  longer offered, its letters kept): `AD/SCA/{Supplier ID}/{YYMM}{NN}`,
  signed by both parties; its clauses are the type's wording (`# Heading`
  a clause, `1.` a numbered point, `a.` a lettered item; Document types);
  the Issue sheet asks its schedules in place of a recipient
  (`#docScaSec`): Schedule A Part 1 from the supplier (legal name, BRN /
  NRIC / Passport, registered address, contact, Start date), Part 2 from
  `doc_types.schedule` (platforms, tasks, reporting, response time, spend
  approval limit, budget tolerance; the Fee typed), Schedule B an account
  a row (the client from Clients, the ad account offered from its Meta
  links, the spend a month in the client's currency, start and end) with
  its notes, kept as `body.agreement` and refused without the legal name,
  start, fee and an account (`agreement-incomplete`, `sca_complete`). The
  PDF (`drawAgreement`, js/letters.js) prints the clauses numbered, both
  signing blocks, then Schedule A and Schedule B (as at its date) as
  tables. A new Schedule B is a Reissue: the same reference, as at the new
  date. No bank
  statement upload (the Jotform field was optional). A document kept
  outside the portal (an agreement, an NDA) is Add existing document's Supplier Letter
  (Documents' ⋯ on the record, or the Register), naming its supplier and no client
  (`register_add` / `register_update` `p_supplier`, `no-supplier`;
  `2026-10-18-supplier-entries.sql`, which filed the entries whose
  reference named a supplier's ID under it); on the record it opens its
  file link, and it is never offered as an email's document.
- A client may also be a supplier; the two are never exclusive (the user,
  2026-11-23: "a clients of ours could also be suppliers of ours"). Every
  flow that reaches one (Bukku, emails, documents, scope) is built and
  tested for a record that is both, each keeping its own acts: a supplier
  whose client holds the Bukku contact links to it as a supplier (Link to
  Bukku offers that contact alone, `bukku-sync` `find` `shared`), never
  read as linked already.
- A supplier that is also a client is linked to it
  (`2026-10-18-supplier-client-link.sql`, `suppliers.client_id`; the user,
  2026-10-18: the Supplier ID and the Client ID stay apart): the record's
  Client group, Link client or Edit (`supplier_client_set`, Suppliers Work
  and Clients View, the client in scope; `no-client`; filed
  `supplier.edited` from and to), the client opening its record; while none
  is linked `supplier_get` names the clients whose BRN, digits alone, is the
  supplier's (Same BRN; `match`, never the BRN itself) and the question
  opens on it. The client's Details name its supplier
  (`client_suppliers`, Suppliers View), opening it.
- Supplier emails (`2026-10-18-supplier-emails.sql`, `supplier-mail`,
  `docs/SUPPLIER-EMAIL-SETUP.md`; the user, 2026-10-18), sent by hand
  through Resend from the suppliers' sender: Send email at the head of Emails (`#supMailSheet`,
  Suppliers Work, a supplier with an email) offers Supplier approved (an
  Active supplier) and Document (a letter not void, sent as its PDF, which
  `supplier-mail` takes only where its title names the reference), the
  words filled from the record (`supplier_email_prepare`) and editable,
  Copy the finance email ticked where it differs; Send asks first.
  Approve asks Send the approval email? (Send email / Not now), and the
  sheet that answer opens sends at its Send with no second question;
  nothing is sent by itself (the user, 2026-10-27, SUP-11). An email
  is filed before it goes (`supplier_email_begin`, refused `recent` within
  `wa_repeat_hours` unless asked again; `supplier_email_done` by its
  sender, filed `supplier.edited`), listed under Emails on the record
  (`supplier_emails_of`) with Resend's word on it (Sent, Delivered,
  Opened, Bounced, Failed, Not confirmed) from its signed webhook
  (`supplier_email_status`, the service role's alone, never stepping
  back); an email still Sending ten minutes after it was filed (its
  function stopped) reads Not confirmed (`mail_sweep`, pg_cron
  `mail-sweep` every fifteen minutes; overdue reminders alike). The two templates (`{contact name}` … `{sender name}`) are
  Settings, Templates: Supplier email templates (`ADspaceMailTpl`,
  Suppliers Full Access or `team.settings`, `email_template_may`). `supplier_email_templates` and `supplier_emails` have RLS on,
  no policy, no grant. The email carries no unmonitored-mailbox line; a
  document's ends Verify this document at digital.adspace.me/verify.
- Send by email (`js/docmail.js`, `2026-10-31-client-document-emails.sql`;
  the user, 2026-10-31: "ok build but still same as whatsapp optionally
  send"): a quotation's ⋯ (not Cancelled, not a website quotation still
  awaiting review, not Do not contact), a Letter of Offer's (not voided or
  replaced) and a client letter's issued in the portal (Documents family
  `client`, not void) each offer Send by email in the Send group beside
  Send on WhatsApp; nothing goes by itself. Gated (the user, 2026-10-31:
  "Enable or disable at business settings"): Settings, Messages: Send by
  email, a switch over every email sent by hand since 2026-11-21 (see
  `docs/rules/messages.md`, The send switches); Off, the act stays drawn,
  disabled with its reason, and prepare and begin refuse `send-off`. Access: Clients: Quotations,
  Clients: Letters, Letters or Documents: Client documents at Work
  (`client_email_may`) with Clients: Contacts at View (its addresses are
  that part's; security audit 2026-11-07), the client in scope. One sheet (`#dmSheet`,
  `ADspaceDocMail.compose`): From the clients' sender, To the client's contacts holding an email,
  the billing contact first, else the primary (`client_email_prepare`),
  Copy the finance email where it differs, Subject and Message the kind's
  template filled from the record and editable, the PDF drawn here as
  Download draws it with Preview PDF, Send asking first and Sent recently
  (the same record within `wa_repeat_hours`) asking again in warn.
  `supplier-mail`'s `client` branch checks the PDF names the record's
  reference, files it first (`client_email_begin`: the record's lock,
  `sending`, `recent` unless asked again), sends through `_shared/mail.ts`
  and closes it (`client_email_done`, filed `client.edited` on the
  client); Resend's word and `mail_sweep` reach `client_emails` as they do
  the supplier's. The record's row reads its last email under its
  reference (Emailed {day} · Delivered; `client_emails_of`, one read a
  visit to the client). The three templates are Clients' Email
  templates (`ADspaceMailTpl`, `team.settings`; filed
  `team.changed` under Client emails). `client_email_templates` and `client_emails` have
  RLS on, no policy, no grant.

- Tax codes per line (`2026-10-22-tax-codes-per-line.sql`; the user,
  2026-10-22: "make the 8% SST inside settings … choose to apply each under
  per item basis", Bukku's own codes): `tax_codes` (code, name, rate,
  active, `bukku_id`; RLS on, no policy, no grant), read by
  `tax_codes_list()` (the team), kept by `tax_codes_save(p_rows,
  p_replace)` (`team.settings`; `bad-row`; filed `team.changed` under Tax
  codes); Settings, Accounting: Tax codes (`#taxSheet`: active first, highest
  rate first, one no longer offered last; one table, Code · Rate · Name ·
  Offered, then the pen and a ⋯, revamp B, 2026-11-04; Edit, Add code, Read from Bukku,
  which lists Bukku's codes (`bukku-sync` `taxes`, asked of `bukku_config`
  as `fields` is; 2026-10-22, BE-12) to tick, those offered
  ticked, and keeps only the ticked ones offered: one unticked is set not
  offered, one never held is never added; each code's ⋯ Delete and Select
  delete through `tax_codes_delete(p_codes)`, all or none, refused
  `in-use` naming each code a service line, a quotation or a letter holds
  (`tax_code_uses`), the count typed back for several;
  `2026-10-22-tax-codes-chosen-and-deleted.sql`). A service line's Tax (`#svTax`,
  `client_services.tax_code`) and a Build quote line's (`.qb-tax`, the
  edit's `tax`; its rate set by `quote_tax_edits` from the table, never the
  page's; `bad-tax`) default to the client's SST (none where exempt) and
  else name an active code. Every total groups the lines by rate and rounds
  each group's SST once (`quote_totals`, `issue_letter`, `priceOf`,
  `quotePrice`; one rate reads as before, to the sen); `issue_letter`
  keeps `tax_code` and `tax_pct` on each snapshot line and refuses a code
  no longer offered (`bad-tax`); `verify_letter` refuses a line whose code
  moved since (`changed-terms`). A letter and a quotation PDF name SST by
  its rate (`ADspaceMoney.sstOf`) and, where the lines are on more than one
  rate, each amount says its own under it, (+8% SST) or (0% SST), never
  under the description (the user, 2026-10-23: it read as the item's). The quotation website keeps the client's
  SST; an issued letter keeps its snapshot. Account, classification code,
  tax inclusive and a line discount are not taken from Bukku.
- Supplier bills (`2026-11-22-supplier-bills.sql`, `supplier_bills`; the
  user, 2026-11-22, the Bukku structure mockup v3, screens a, b and c-alt):
  every supplier's purchase bills, read only, from the nightly copy
  (`bukku_docs` kind `bill`, a contact linked to a supplier; never a
  creator's), at Suppliers View (Sensitive details shuts the bank details
  alone). Suppliers' view strip reads Suppliers · Payments (`#supViews`,
  `view=payments`, its overdue bills counted in red; stepping away while a
  record is open), four tiles over the list (`#supTiles`: Active
  suppliers, Pending approval, Awaiting payment and Overdue bills, a figure
  a currency, the oldest overdue in red). Payments (`#spyView`): the
  tallies (Awaiting payment, Overdue, Due in 7 days, Paid this month), then
  Overdue, Awaiting payment and Paid within its period (`#spyPeriod`), a
  `.cpq-row` a bill (the supplier and its bill number, the Supplier ID and
  the client seen), Open in Bukku on each; Read from Bukku at Suppliers
  Work. No bill is made in the portal. The record is the creator's grid
  (`.rec.crr-body`): the strip and the pane, and a rail of Totals (Billed,
  Paid, Outstanding, Overdue, a line a currency) and Bill history (Bills, Last
  bill, Last paid), following the pane on a phone; Payment holds Bills
  under the Bukku band (`#supBills`, overdue first, each a `.cpay-job` on
  the phone row with a ⋯ of Open in Bukku; No bills. when none), and its
  tab counts an overdue bill in red (`tests/supbills.js`, `supbillsql.js`).
- A supplier's Edit sends only the fields that moved, with `expected` (the
  copy's `updated_at`) inside `p_values`; `supplier_save` lays the stored
  row under what was sent, refuses `stale` with the supplier as it stands,
  and the page repaints and says `ADspaceWords.line.stale`
  (`2026-11-24-supplier-save-version.sql`, `tests/suppliersql.js`,
  `tests/editstamps.js`).
