<!-- triggers: js/bukku.js js/invoices.js js/payments.js supabase/functions/bukku-sync -->
# Bukku (`js/bukku.js`, `bukku-sync`, `2026-10-18-bukku-contacts.sql`, `docs/BUKKU-SETUP.md`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- Phase 1 (the user, 2026-10-18: quotations, invoices and purchase orders
  are made in Bukku): a client's billing and an approved supplier's details
  are sent by hand as one Bukku contact. Billing's Bukku group and the
  supplier record's (`ADspaceBukku.group`: Contact, Last sent, Since then;
  Send to Bukku at Clients: Billing Work, Suppliers Work) open `#bkSheet`:
  the linked contact, else the contacts with the same registration number,
  then the same or a similar name (`find`, every page read), and New
  contact under Bukku's own next code (`C-{first letter}{nnnn}`); what
  changes field by field (`preview`); Send, Link and send where it links.
  What goes is `bukku_prepare`'s answer as the colleague (a company's name in
  capitals, a person's each word capitalised, `bukku_name_case`; the NRIC
  at `suppliers.pay` alone, the bank details never), the Client ID or
  Supplier ID in the Bukku custom field chosen on Settings, Accounting, Bukku
  (`bukku_config_set`, `team.settings`; `no-field` until chosen). An update
  reads the contact first and keeps Bukku's code, terms, accounts, groups,
  other people and addresses; its types gain Customer or Supplier and never
  lose one; nothing is deleted or archived in Bukku (`tests/bukkufn.js`).
  The address is read into Bukku's parts (street, postcode, city, state,
  country; a line break a comma), and an address or a billing person Bukku
  already holds however set out (the same letters and digits; every word of
  ours in Bukku's name) is kept; the person goes with the contact's
  salutation (`bukku_prepare` `salutation`), put before a name Bukku keeps,
  in place of a salutation Bukku's name opens on, never both;
  a person or address added ticks default billing alone, never default
  shipping; a supplier's payment term is set as Bukku's own term of the same
  days where Bukku holds one (the user, 2026-10-19). Sending to a contact
  Bukku holds, each change is a tick (`#bkRows input[name=bkSend]`, all
  ticked, the type never), an unticked one sent as Bukku holds it
  (`skip`, `keepAsHeld`; the user, 2026-11-10: "choose which one to
  send") and never copied back to the portal: while one still differs the
  link is not held and reads Differs from Bukku (`takeAfterSend`, audit
  2026-11-11); a state goes under Bukku's own name (Penang as Pulau Pinang,
  `STATE_AS`: Bukku refused Penang), and Bukku's refusal names its fields'
  reasons, never only "The given data was invalid.". Link only (`#bkLink`,
  beside Link and send for a contact Bukku holds; kept apart from Link and
  send, the user, 2026-10-31) links it as it stands and sends nothing (`bukku-sync` `link`, `bukku_link_only`, filed Linked to
  Bukku, nothing sent; `2026-10-19-bukku-as-bukku-holds-it.sql`). What a
  record lacks (`bukku_prepare`) is read with the group: a record that
  cannot be sent draws no Send and says what is missing in one line
  (2026-10-20, BKU-1).
  The link is filed by `bukku_linked` (`bukku_links`, `bukku_settings`: RLS
  on, no policy, no grant; filed `client.edited` / `supplier.edited` Sent
  to Bukku · code); a supplier linked to a client is that client's contact.
  The record shows it as one shaded band at the foot of what it sends
  (`.bk-band`; the user, 2026-10-29: the group "looks incomplete"): Bukku,
  the contact's code and its state (Up to date, Details changed once a sent
  field moves (`bukku_print`), Not linked), Last sent under it, Send to
  Bukku and a ⋯ of Unlink at the right edge. Unlink (`bukku_unlink`, the
  record's Work level, asked first) lets go of the link alone, nothing
  changed in Bukku, a supplier and its own client together (one contact),
  kept in `bukku_links_gone` (RLS on, no policy, no grant) for Undo where it
  happened (`bukku_unlink_undo`: as it stood, `moved` once linked again),
  each filed Unlinked from Bukku / Linked to Bukku again
  (`2026-10-29-bukku-unlink.sql`, the SQL Editor's); Send to Bukku then
  offers the matching contacts again.
  One Bukku contact is one record's, a supplier and its own client sharing
  one: `bukku-sync` sends a linked record to its own contact alone and asks
  `bukku_contact_check` before it writes Bukku, and `bukku_linked` and
  `bukku_link_only` refuse `taken` (2026-10-22, BE-2). A contact the page
  names for an unlinked record is read or written only where find offers it
  for that record (its registration no. or name), else `not-offered` unless
  the colleague sees every client (`invoice_scope` `all`; security audit
  2026-11-07).
  Bukku by entity (`2026-10-29-bukku-by-entity.sql`, the SQL Editor's; the
  user, 2026-10-29: one brand billed by several companies): a Bukku contact
  is a company, so `bukku_links` takes the kind `entity`; an entity's fold
  on Billing holds its own band (`.ent-bk`, read as it opens), Send to
  Bukku, Link only and Unlink at Clients: Billing Work on a client it bills
  that the colleague sees (`bukku_may`); what goes is the entity's
  registered name, numbers, address, finance email and billing contact
  (else its brand's primary contact), with the Client ID and market of the
  brand it is filed under (`entity_home_client`: the brand it is the
  primary of, else the first to add it); each step filed `client.billing`
  on every brand it bills, the company named (`bukku_file_entity`). A brand
  and its primary entity are one company and may hold one contact; any
  other two records may not (`bukku_contact_taken`); a record with no link
  of its own reads its company's, said as Linked through (`bukku_shared`).
  Billing from Bukku (`2026-10-30-billing-from-bukku.sql`; the user,
  2026-10-29: "we dont need two sides update", option A approved
  2026-10-30): once a client or a billing entity is linked and held, Bukku
  holds its billing and the portal's columns are its copy. An unlinked
  client or entity offers Link to Bukku (the user, 2026-10-30: "use link
  bukku instead of send to bukku"): its sheet links the contact chosen as
  Bukku holds it, nothing sent (Link, how the details differ shown), or
  makes New contact in Bukku (Create in Bukku). A link is held
  by Send to Bukku, or at its first read where every detail that differs
  is empty in the portal; one made by Link, or standing before, whose
  details differ reads Differs from Bukku, field by field, with Send to
  Bukku and Use Bukku's (asked; `bukku-sync` `hold`), nothing replaced
  until one is chosen. The band then leads Billing (`opts.lead`): Linked,
  Read {day, time}, Refresh and the ⋯'s Unlink, no Send and no Details
  changed; Billing is read once a visit to the record (`bukku-sync` `read`,
  one read at a time a record), a change made in Bukku taken in and said
  once on the band (Changed in Bukku since the last read), filed by Bukku;
  Bukku's billing person is the contact whose name, or every word of whose
  name, Bukku's holds (Angel in Ms Angel Lim; the only such contact,
  `bukku_person_contact`, `2026-10-30-bukku-person-by-its-words.sql`), as
  Send to Bukku keeps Bukku's whole name; one not in Contacts is said on
  the band with Add as contact, a `.btn-sm` at the line's right edge.
  Edit's Save reads Save to Bukku and sends only what changed
  (`bukku-sync` `save`, `bukku_prepare_with` as the caller, every other
  Bukku detail kept as Bukku holds it), refused `stale` where Bukku moved
  since the read (read in, the sheet kept), Undo where it happened writing
  the earlier values back; SST on quotes and Bill in stay the portal's.
  Bukku not answering reads Not read with the copy's time and draws no
  Edit; Use details from the client's form fills the same sheet and saves
  to Bukku. `bukku_take` (the service role's) writes only the fields that
  differ (a registration no. Bukku sets out otherwise is the same one),
  stamps the row, and writes the copy to the
  record's primary entity (to the brand through `billing_entity_mirror`)
  and files `client.billing` naming the fields (Read from Bukku by Bukku,
  Saved to Bukku, Took Bukku's details); every held link is read again at
  00:30 MYT (pg_cron `bukku-read-nightly`, the wake secret, 100 seconds a
  run: creators' bills first to 35 seconds, months' invoices to 60, the
  payment history (Payments, below) to 80, then the links, the oldest read first, in what is left; the run writes its beat,
  `job_beat('bukku-nightly')`, which `jobs_watch` reads; audit 2026-11-15). An entity is the same inside its fold.
  A supplier links as a client does (`2026-11-22-supplier-bukku-link.sql`;
  the user, 2026-11-22: "Link clients, Link creators, But no link
  suppliers?"): unlinked, its band offers Link to Bukku (Link as Bukku holds
  it, nothing sent, or Create in Bukku), and once linked the band leads
  Payment and reads Bukku as the record opens (`bukku-sync` `read`, Suppliers
  View): Linked, Read {day, time}, Refresh and the ⋯'s Unlink; where they
  differ, Differs from Bukku over the `.bk-diff` table with Send to Bukku and
  Use Bukku's (`hold`, Suppliers Work, filed `supplier.edited` Took Bukku's
  details). Unlike a client's billing, a supplier's details stay the
  portal's: a read never writes them (`bukku_take` answers what differs) and
  Edit saves in the portal (`save` is refused). It compares its own fields
  (`bukku_portal` `fields`: name, BRN for a company, TIN, SST no., finance
  email else email, address, person in charge), never an individual's NRIC,
  which is neither answered from Bukku nor taken (`onlyFields`); the send
  sheet shows an individual's Bukku registration no. only to a colleague
  who may send it. Linked, its bills of the last 24 months are read at once
  (`supplierBillsOf`), never only overnight; the nightly run reads clients'
  and entities' links alone. A colleague is a Bukku employee
  contact (kind `member`, `2026-11-17-bukku-employee.sql`, its SQL Editor
  part turning it on; HR-SPEC decision 12): the band on their Onboarding
  at `team.personnel`, sent with the name as per NRIC, the company email,
  the mobile and the home address, never an NRIC, a bank account or a
  salary, no Bukku field holding the Employee ID; filed `team.edited`;
  `bukku_member_ready()` keeps the band away until `bukku_links.kind` takes
  `member`. Creators brought in from the
  AP01 form are matched to their Bukku contacts by `bukku-sync`
  `match-creators` (the wake secret alone, read only: ID number, else one
  contact of the legal name, a contact another record links said as
  taken; `creatorMatches`); the links are then made as Link only makes
  them (2026-11-11, the user: "yes link").
  Secrets `BUKKU_TOKEN`, `BUKKU_SUBDOMAIN` (Supabase only).
- Overdue invoices (`js/invoices.js`, `2026-10-28-overdue-invoice-reminders.sql`;
  the user, 2026-10-28: "pull those overdues data from bukku and inside
  Portal and selectively send by users", Bukku's own reminder "fully bukku
  labeled"): Clients' second view (`#crmViews`, Clients / Overdue invoices,
  `view=overdue`), at Clients: Billing View. `bukku-sync` `invoices` reads
  Bukku's Outstanding and Overdue lists (every page, each invoice once)
  when the view opens and on Read again, never stored and never polled,
  held by `invoice_scope()` (as the colleague) to the Bukku contacts linked
  to a client they see (a contact linked to a billing entity bills every
  brand the entity bills: `clients`, its company `company`, its recipient
  the entity's billing contact and finance email, `invoice_recipient_for`;
  2026-10-29), one linked to no client only for a colleague who
  sees every client. An invoice is overdue where its balance stands and
  its due date (its one term, else the invoice's date) is before today
  (MYT); with instalments, the part past its date (`overdueOf`, a term's
  balances read in full where the list holds none, and where even the
  invoice read whole holds none, what is paid set against the terms'
  amounts in date order, else the whole balance from the earliest date
  passed, `overdueWhole`, never taken for paid), named by the terms it
  covers (Instalment 2 of 3, Instalments 1 to 2 of 3; `partWord`). One
  client's Billing asks Bukku for its contacts alone, and a colleague
  seeing no linked client asks nothing (2026-10-29). A card for each age
  (Over 90, 61 to 90, 31 to 60, 1 to 30 days), totals per currency, never
  added across; each row its last reminder's status (`invoice_reminders`),
  a bounce with Open contacts, Open in Bukku (Bukku's own host alone). At
  Clients: Billing Work the rows are ticks: Send reminders opens Review and
  send (`#odSheet`): one email a client, the clients at the left, the
  email at the right as it arrives, Edit (on the Subject's line, at its
  right edge) changing that client's subject and message alone, Sent before as a table (When, Channel, Sent by,
  Status). Send asks first (Send again where a client was reminded within
  `wa_repeat_hours`, asked again for that client alone; one reminded by a
  colleague meanwhile is refused `recent` and asked about at the next
  Send), then `bukku-sync` `remind` reads each invoice from
  Bukku again, five at a time (one paid, voided or not yet due since is
  left out and named as such), files it first by
  the service role (`invoice_email_begin`: the contact's lock, `sending`,
  `recent` unless asked again, the billing contact greeted with their
  salutation else the main contact, sincerely to a name and faithfully to
  a company, the finance email copied where ticked; an invoice number of 1
  to 60 characters with no control character), builds the table where
  `{invoices}` stands (a View PDF a row for several, one small button for one,
  from Bukku's share link), sends through Resend from the finance sender, and closes it
  (`invoice_email_done`, filed `client.edited` on the client). A page never
  files or names a figure: begin and done are the service role's alone.
  Shut while sending, Review and send sends no further email and reads the
  list again once the one on its way answers. Once every email has gone
  its foot holds Done alone, tonal, never blue (it only shuts the sheet;
  the user, 2026-11-10).
  The words are Settings, Messages: Email templates, Overdue reminder (`invoice_email_template`,
  `team.settings`; two subjects, the message holding `{invoices}`, the
  legal note and the disclaimer, in the dark grey). Resend's word
  reaches it through `supplier_email_status`. `invoice_emails` and the
  template have RLS on, no policy, no grant. A client's Billing (the
  user, 2026-10-28) holds Unpaid invoices (`#odClient`,
  `ADspaceInvoices.client`): `invoices` with `client`, the contacts of
  every company billing that client (its own, its entities') alone, each
  company under its name where there are several (`.od-co`; the user,
  2026-10-29: "All related entities should be shown as well"), and its
  invoices not yet due as well (Not due); a reminder sent there is filed on
  that client and addressed to the company it is for,
  Send reminder while one is overdue at Billing Work (the same Review and
  send), and its Emails sent (a reminder or an invoice, which and when);
  read on each visit to the pane, drawn
  only for a client linked to a Bukku contact (Bukku's group above says
  when it is not). No Bukku branding; WhatsApp
  reminders are not built (the user, 2026-10-28: "dont build the whatsapp
  first").
- Payments (`js/payments.js`, `2026-11-19-payment-patterns.sql`; the user,
  2026-11-19: each client's and entity's payment patterns, "act like you are
  those CFO metrics … estimate and predicts the payments inwards outwards"):
  Clients' third view (`#crmViews` Payments, `view=payments`, `#pynView`), at
  Clients: Billing Full control alone (`payment_analysis` refuses `denied`
  below it; Sensitive details off shuts it with Billing), held as Overdue
  invoices are (`invoice_scope()`). Unlike Overdue invoices it is read from
  a copy: `bukku_docs` holds Bukku's sales invoices of the last 24 months and
  suppliers' purchase bills (kind `invoice`, `bill`), written only by
  `bukku-sync` through `bukku_docs_take` (the service role's; RLS on, no
  policy, no grant, as `bukku_doc_marks`, the history's reach): the nightly
  run (to 80 seconds, after the months' invoices; a failure is the beat's
  detail) and Read from Bukku (25 seconds, asked as the caller first), each
  reading the last 62 days and every invoice owing, then whole the ones
  whose due date or paid day is not known or that stopped owing (24 a run;
  one Bukku no longer holds marked gone, never deleted), then one month
  further back until 24 months are held; nothing is written to Bukku. A due
  date is the last instalment's, else the invoice's date; the paid day is
  the latest payment applied (`paidOn`). One currency at a time (the
  Currency pill, never added across). The figures: days sales outstanding
  (open against the last 90 days' invoicing), and over the invoices paid in
  the last 12 months days to pay (invoice to paid), days paid late (due to
  paid, early counting none) and paid on time, each judged against the 12
  months before by `ADspaceSales.judge`; the open receivables by age (Not
  due, 1 to 30, 31 to 60, 61 to 90, Over 90 days); 13 weeks from this
  Monday of money in (each open invoice at its due date moved by its
  payer's average days from due to paid over 12 months, else everyone's,
  never before today) and out (creators' unpaid bills, `creator_bills`, by
  their booking's Pay by, else their date, and suppliers' by their due
  date; a creator's held to its campaign's client, a supplier's to its
  client, one with no client only for a colleague seeing every client); a
  row a payer (a Bukku contact, named by the company billed, else its
  client, else as Bukku holds it), the most owed first, a linked one
  opening the client's Billing (`tests/payan.js`, `payanfn.js`,
  `payansql.js`).
- Send invoice (`2026-11-04-invoices-sent-by-email.sql`; the user,
  2026-11-04: "send invoice (pulled data and pdf from bukku) send to
  clients email", approved "attach link for now"): each unpaid invoice on
  a client's Billing, due or not, carries Send invoice at Billing Work,
  opening the same Review and send as Send invoice; the invoice is sent
  whole (its balance, never an instalment), read again from Bukku at the
  press (`bukku-sync` `deliver`: paid or voided since, `nothing-unpaid`,
  said for what it is), filed first as `invoice_emails.purpose` invoice
  (`invoice_send_begin`, the service role's, over the one filing both
  sends share, `invoice_mail_begin`), from ADspace Finance with the same
  table and Bukku's own link (View PDF; Bukku's API holds no PDF to
  attach), and closed as Invoice emailed to … on the client. Its own
  words (`invoice_send_template`, Settings, Messages: Email templates, Invoice email,
  `team.settings`; `invoice_send_template_get`, `_save`, filed under
  Invoice email) and its own Sent recently: a reminder never holds an
  invoice back, nor an invoice a reminder. The Email log reads it as
  Invoice.
- To and Copy are chosen (`2026-11-04-invoice-recipients-chosen.sql`; the
  user, 2026-11-04: "only related to the client contacts"): Review and send
  (a reminder or an invoice) reads `invoice_recipients(p_client, p_contact)`
  (Billing View, the client in scope) once a client: To a select of the
  client's live contacts holding an email, its finance email and the
  billing contact it goes to by default (first, chosen), Copy a tick for
  each other one (the finance email ticked, five at most); never an
  address typed in. `bukku-sync` sends `to` and `ccs` to
  `invoice_mail_begin`'s thirteen-argument form, which refuses any address
  `invoice_recipient_options` does not hold (`bad-recipient`, `bad-copy`)
  and greets the contact chosen (the finance email Sir or Madam); every
  copy is sent (`cc_list`) and filed in `cc_email`, comma separated.
- Quotation invoices (`2026-11-17-quotation-invoices.sql`; the user,
  2026-11-17, option B): an approved quotation's row act Invoices
  (Clients: Billing View or Quotations View) opens `#qiSheet`, a row a billing cycle of the
  term from the day its confirmed lines start (`quotation_start`; the 16th
  runs to the 15th, never pro-rated) and a row a cycle for the advertising
  budget; Create in Bukku (Billing Work) asks `quotation_invoice_prep` as
  the caller (`not-reviewed`, `no-start`, `not-linked`, `invoiced`,
  `creating` for ten minutes, the quotation's row locked first so two
  presses at once hold one; `no-budget-account`, `no-tax-code`), then
  `bukku-sync` `invoicecreate` searches Bukku for an invoice holding the
  reference whole in its second number (`{ref} · {cycle day}`, ` · Ads`;
  never a match inside a longer one, the budget's holding the service's)
  and makes none twice, else
  makes one draft: each line on the Bukku product of its Rate Card SKU
  (`no-sku`, `no-product` name the line), its income account the
  product's, its rate after the line's own term percentage, each term
  percentage and SST rate's lines totalling the quotation's own figure to
  the cent (the group's last line carrying the sen rounding leaves,
  `2026-11-17-quotation-invoices-to-the-cent.sql`), its tax code
  Bukku's; the budget on the account code set in Settings, Accounting, Bukku
  (`bukku_invoice_set`), no tax, to the contact chosen for the client
  (`client_ad_debtor_set`), else the client's own; filed by
  `quotation_invoice_done` (`client.billing`). `quotation_invoices` and
  `client_ad_debtors` have RLS on, no policy, no grant.
  A created cycle reads Paid or Unpaid from the nightly copy (`bukku_docs`
  by the Bukku id filed, not gone; `2026-11-22-quotation-invoice-paid.sql`),
  Draft until finance approves it in Bukku, its number on the line under
  it. Invoices is offered at Clients: Quotations View as well as Billing
  View: `quotation_invoices_of` answers the amounts, the budget's contact
  and its account at Billing View alone (`billing`), `denied` below both.
- Bukku not connected (SWITCHED-OFF ACTS, 2026-11-21): every act that asks
  Bukku (Send to Bukku, Link to Bukku, Refresh, Use Bukku's, Create bill,
  Create n bills, Read from Bukku, Overdue invoices' Refresh) carries
  `data-gate="bukku"` and is drawn disabled with its reason while
  `bukku_ready()` reads no nightly read (`job_beats` `bukku-nightly`) in
  three days; Open in Bukku (a link to Bukku's own site) is never held.
- Supplier bills (`2026-11-22-supplier-bills.sql`): Suppliers' Payments
  view and a supplier's Bills read `supplier_bills` (Suppliers View, as the
  caller) from `bukku_docs`; `bukku-sync` `supplierbills` (Read from Bukku)
  asks it first and reads the suppliers' bills alone for 25 seconds at
  Suppliers Work (`work`), `supplierbilllink` names a bill's page only
  where the caller reads that bill. Open in Bukku is a `.btn-sm` at its own
  width or a ⋯ item, never a row's width (the user, 2026-11-22).
- A Bukku bill or invoice reads its number with the reference no. Bukku
  keeps beside it (`number2`), `AB2609081 / Reference: XXXX`
  (`ADspaceWords.line.docNo`; `2026-11-23-supplier-reference-no.sql`; the
  user, 2026-11-23): a supplier's bills, a creator's bills and Overdue
  invoices alike, searched by it too; kept alone as `ref_no`
  (`bukku_docs`, `creator_bills`, a live invoice line), never joined into
  a creator bill's `ref`. An email's invoice table keeps the number alone.
- A field newly read from Bukku onto a kept document (`bukku_docs`) sets
  `bukku_doc_marks.back_to` to null for its kind in the same release: a
  run re-reads only the last 62 days and one month further back, so rows
  already held would never take the new field (2026-11-23: the reference
  no. read empty on every bill older than 62 days).

## Components

Moved from DESIGN.md §4 on 2026-11-23.

| Need | Component |
|---|---|
| A record's link to another system (Bukku) | `.readgroup.bk-band`: a `--sunk` band, Bukku's own logo 16px high (`ADspaceBukku.mark`, `img/bukku-logo.png` from bukku.my/brand/bukku-logo.png at three times its size, the same file in both themes (never recoloured; the user, 2026-11-11), the word kept for a screen reader; the Settings row the same; never on a client page or an email), the code in the token face as a copy control (`.serial-copy`, pressed to copy it; the user, 2026-10-30), its state as `.chip-state`, one 12.5 mute line under it, the acts as `.btn-sm` and a ⋯ (Unlink) at the right edge, on their own line when the pane is tight. Not linked, it closes the details it would send (Link to Bukku on a client or entity, Send to Bukku on a supplier); linked, it leads them: Linked over Read {day, time} with Refresh, Differs from Bukku with Send to Bukku and Use Bukku's over a `.bk-diff` table (Field, Portal, Bukku; narrow, the field heads its row), Not read with the copy's time and Try again; a billing person Contacts lacks is the warn line with Add as contact (`.btn-sm`, its plus) at its right edge (`.bk-person`) |
