<!-- triggers: js/crm.js js/engage.js js/sales.js js/checklists.js js/details.js details/ supabase/functions/brand-analysis supabase/functions/checklist-draft -->
# Clients (`js/crm.js`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- Four bands (the user, 2026-10-08: Paused folds on its own):
  - Leads;
  - Clients (active);
  - Paused;
  - Past clients (shut by default, remembered, keeping their count).
  - Each band draws thirty, then Show N more.
- Columns: Client, Stage, Industry, Person in charge, Sales by, Last activity,
  chevron (Sales by the colleague's name, a mute em dash where none, named
  only once the team is read; the user, 2026-11-07).
  - Filters: Stage, Person in charge, Sales by (`#crmSales`, by the
    colleague's id) and VIC while any is held (the user, 2026-11-09).
  - No Value column and no value on a heading.
  - Rows run newest Client ID first (digits as numbers), unnumbered after,
    newest first.
  - The row is one `<button>` with nothing nested.
  - The client's logo leads the name cell (`.cl-mark`, 32px, 28 on a phone;
    the record head's white disc, initials only while none is held or where
    it fails to load), and the Client ID sits under the name in the token
    face and is searched; on a phone it leads the meta line instead
    (`.crm-meta-code`), which reads Client ID · one person (`metaPeople`): Active
    and Paused the Person in charge, a lead and a Past client the Sales by,
    else the Person in charge; Industry and Last activity left to the desk
    and the record (the user, 2026-11-04; 2026-11-13).
  - On a phone the row is two columns: name over meta, and the chip over the
    age in a fixed 120px track, top aligned. The meta omits what is not known,
    never showing a bare currency sign.
- Last activity (`loadLastSeen()`, one read: `client_last_activity()`,
  invoker, the newest of each kind a client): the newest of a logged call or visit, a
  stage move (`stage_since`; `Added` while it has never moved), or a document
  issued. The date sits over a mute word for which one.
  - A refused read is left out.
  - A future date never counts.
  - Nothing reads as a mute em dash.
- The Client ID (`^[A-Z0-9]{2,12}$`, unique) is load bearing: the letter
  serial uses it. A client becomes Active only holding one (the user,
  2026-10-18: a lead may come to no deal): the move asks for it, the next
  AC number offered (`client_code_next()`, one past the highest across
  every client, as wide as it), and both go in one write; trigger
  `clients_active_code` refuses Active with none (`active-needs-code`;
  `2026-10-18-client-id-at-active.sql`). A Letter of Offer before Active
  still asks for one at its Reference.
- The slug is set once from the name, never follows a rename, and a clash is
  numbered, a clash only the index sees (a client outside the colleague's
  scope; every Chinese name reads `client`) taking the next number, never
  the database's words (2026-10-19). It lives only in the console address (`clientByKey()` resolves a
  slug or a UUID by shape) and never grants access.
- Stage clock: `stage_since` and `stage_log` are stamped by
  `clients_stage_clock`, and only a real move restarts it. After a move the row
  is re-read (`refreshClient`). The move is tagged `client.stage`.
- Paused and Past say why (`2026-10-04-client-leave-reason.sql`): the stage
  select asks first (`askLeave`: Reason, required, of Budget, Results, Moved
  in-house, Business closed, No reply, Completed, Other, Completed offered
  only for a move to Past of a client once Active and held so by
  `clients_stage_reason` (`2026-11-15-completed-reason.sql`, a one-time
  project finished as agreed); an optional note; the client's
  open tasks counted by `client_open_tasks`, "3 tasks are still open. They
  show as urgent delivery in My Work."), the select holding its stage until
  the answer. `clients.stage_reason` / `stage_note` ride the update and the
  clock keeps them on that move's `stage_log` entry; a move into Paused or
  Past without one is refused (`stage-reason`), and a move anywhere else
  clears both. The Timeline names the reason under the move, a pen at
  Manage: the reason and note are changed later (`ADspaceConfirm`, that
  entry of `stage_log`, and `stage_reason` / `stage_note` while it is the
  stage now; `.select('id')`, filed `client.edited` from and to); the
  activity row carries it. `clients_stage_notice` tells each owner of the client's
  open work once (`client_left`, "{client} moved to Paused · 3 open tasks to
  deliver", opening My Work).
- A stage set ahead (`2026-11-24-client-stage-ahead.sql`, CLIENT STAGE AHEAD;
  the user, 2026-11-24: "if some client has told us to end for the
  following month, so we could mark it first"): the Paused and Past
  question asks an Effective date (today by default, never earlier); today
  moves the client now, a later day writes `clients.stage_next`,
  `stage_next_on`, `stage_next_reason` and `stage_next_note`, one a client,
  and the client works in its stage until then. Trigger
  `clients_stage_next` holds the day after today in Malaysia
  (`stage-next-day`), another stage (`stage-next-same`) and Completed for a
  client once Active (`stage-next-reason`); `clients_stage_next_shape` all
  four or none; any real move of the stage, by hand or by the job, lets it
  go, so a stage set by hand meanwhile replaces it. `clients_stage_due()`
  (pg_cron `clients-stage-ahead`, 00:01 Malaysia) makes the move on the
  day with its reason and note through the stage clock, filed
  `client.stage` under system ({Stage} from {day}, as scheduled · {reason});
  a stored move, not a stage derived on each read, since about three
  hundred lines of the schema read `clients.stage` (every policy through
  `client_row_seen`, the client portal, Active clients alone in Content
  Review, campaigns and reports), so on the day every one of them sees it
  at once. The record head reads it under the meta (`#crmAheadLine`: Past
  from 1 Dec 2026 (Tuesday) · Completed, then Edit and Withdraw at the
  band's Work; Edit the same question filled in, refusing today; Withdraw
  with Undo where it happened while the day is ahead); the list row a grey
  chip after the name (`.crm-ahead-tag`, Past from 1 Dec), the client kept
  in its band; each set, change (from → to) and withdrawal filed
  `client.stage` (Scheduled: …; Scheduled change withdrawn: …). The
  Dashboard and Analytics: `docs/rules/dashboard.md`,
  `docs/rules/analytics.md`.
- No Sales view (removed 2026-10-12, the user: "Priority is the dashboard";
  what it held that the Dashboard did not moved there); an old
  `view=sales` address opens the list. `js/sales.js` is the figures alone
  (`ADspaceSales.figures`, `reasonWord`, and `judge`, the one Better, Worse
  or Steady the Dashboard's tiles and Analytics both read; 2026-11-12), read by the Dashboard from each
  client's `stage_log`, `stage_reason`, `source` and `owner`: Won is a
  lead's first move to Active (or a client keyed in Active, or a lost lead
  later Active), each from `eventsOf` and counted once (the user,
  2026-11-15: an ended engagement waits in Paused before Past): Churned a
  client's first move out of Active into Paused or Past, Completed in its
  place where that move or the Paused to Past after it is Completed (never
  churn), the later Paused to Past counting nothing; Lost a lead never
  Active at its first move into Paused or Past; a leaving counted in a
  period only where its last move there leaves the client out of Active;
  Paused every move into Paused; Resumed Paused back to Active, a Win-back
  Past back to Active (a former Active client); Committed
  monthly value a month of each confirmed monthly line (a term over one
  month, started by today) by market, never added across currencies.
- The follow-up limits (`staleH(c)`, settings `lead_followup_hours` 48 and
  `proposal_followup_days` 21, calendar days; a VIC client's
  `vic_lead_followup_hours` 24 and `vic_proposal_followup_days` 7,
  `2026-10-15-vic-followups.sql`, under VIC clients in the same sheet):
  - Lead and Proposal sent read Overdue past theirs;
  - Contacted has no limit.
  - An over-run stage reads "N days · Overdue" in red, and the group head
    counts them.
- Intake: Brand name (the trading name; the registered name belongs to Billing),
  Source, Salutation (the contact sheet's own list; 2026-10-14), Contact person, Phone, WhatsApp username, Email, Enquiry, Owner,
  Industry (from Settings, Partners, Clients: Industries, below), Market, Urgency to commence (`clients.commence`, blank until
  asked; Within 3 months, 3 to 6 months, More than 6 months). After intake the enquiry is edited like any other fact, and a person
  becomes a row in Contacts. Under Own clients only the Person in charge is
  fixed: the colleague keying a lead holds it. Sales by (`crmSalesBy`, More
  details) is the colleague keying a new lead, changed only at Clients Full
  Access (trigger `clients_sales_by_guard`, `sales-by`), filed from and to,
  and read under Details. A contact refused after the
  client is made is said, and what was typed waits in the contact sheet on
  the new record (2026-10-19).
- Industries (`2026-11-04-industries.sql`, its SQL Editor part
  `2026-11-04-industries-editor.sql`; the user, 2026-11-04: "can do a
  setting for industry?", then "A", then "option 1 … 3 or 4 columns"):
  `industries` (name, name_zh; RLS on, no policy, no grant), seeded with
  the nine the portal offered (F&B and Tech as Food and beverage and
  Technology, their clients moving with them). `industries_list()`, A to Z
  with Other last, answers the team each with how many clients hold it and
  anyone else (the quotation website) the names alone; the console's
  Industry and `/quote/` read it once a visit, and `quote_website_create`
  takes only one it holds (`bad-industry`). Settings, Partners, Clients: Industries
  (`#indSheet`, `team.settings`): one table, English · 中文 · Clients · the
  pen; the pen turns its row into the two fields (Enter saves, Escape
  leaves), Delete in that row only where no client holds it (asked,
  `in-use`); the last row adds one; `industry_save(p_was, p_name,
  p_name_zh)` (`bad-name`, `bad-name-zh`, `taken`, a rename onto another
  name included), a rename carrying onto every client holding the old
  name, those outside the caller's own client scope too (`adspace.team_owner`
  for that update, `2026-11-04-industry-renames.sql`); Enter twice while a
  row saves is one save, both tables' keys one helper (`rowKeys`); /quote/
  refused an industry renamed meanwhile (`bad-industry`) reads the list again
  and asks for it in words; Other keeps its
  English name and is never deleted (`fixed`), so it stays last; each filed
  `team.changed` under Industries. A client holding a name the list no
  longer holds keeps it in its picker; a list that cannot be read is said
  under the field with Try again (`#crmIndMsg`).
- The Clients list, and every read of all clients (`bridge.active`,
  `uniqueSlug`, the Dashboard), is read a thousand at a time
  (`ADspaceAPI.readPages`, the one copy; 2026-10-19); past its cap it
  answers `too-many`, never a list cut without a word (2026-10-22, BE-14).
- A client's address outside the colleague's reach (or gone) lands on the list
  with `#crmListMsg` saying so, never silently.
- The record head `.rec-id` (`auto minmax(0,1fr) auto`, centred):
  - Mark: `logo_url`, or `initialsOf()` (two characters of a Chinese name; else
    the first letters of the first two words that start with a letter).
  - The name and its meta (the main contact's preferred language and the person
    in charge; each left out when unknown).
  - `.rec-ctl`: Log call (`#crmLogCall`, Clients: Calls at Work, the phone
    glyph alone on a narrow pane, given to the pane's own head on Calls and
    visits, and gone from a head under 300px (`data-narrow="300"`, a 320
    phone); 2026-10-11), the stage select, then one ⋯ holding Edit and
    Delete (the item carries `data-need="clients:manage"`).
  - Phone (`.is-narrow`): `"mark . ctl" / "who who who"`.
  - The month line (`#crmMonthLine`, 2026-10-08), under the meta for an
    Active or Paused client and a reader of My Work: the month whose span
    holds today, `n of N done` (`ops_engagement_counts`), the overdue count
    and Report due (the span's end plus `report_due_days`) where the month
    owes one, led by its dot (red with any overdue, green when all done,
    else amber); it opens the client's Months view. It is read from the
    Engagements pane's answer, never a read of its own.
- Panes (`tab=`, pushed to history; Overview stays out of the address):
  six tabs, never more (the user, 2026-10-15: the strip "gradually
  increasing"; again 2026-11-24: a new part joins a tab, never the strip;
  `tests/engage.js` counts them), each
  showing its parts one under the other (`#crmPanes`, 24px apart), each
  part keeping its heading and its own address (`tab=billing` opens
  Account on Billing, so every older link lands):
  - Overview; Interactions (2026-11-24): Calls and visits (`tab=calls`,
    Clients: Calls, never behind the Activity record's access; 2026-10-11)
    then Feedback (`tab=feedback`), each its own card with its count and
    its act on its head (Log call; Request feedback, then out of the
    record's ⋯); Engagements (the months,
    drawn for a client engaged now or before or holding anything, then
    Checklists; the tab stays for a lead's checklists); Services
    (Quotations and Service lines, with Requests once a contact has portal
    access or a request exists, then Documents, so a letter is issued where
    its lines are; the user, 2026-10-19: "when creating documents it has to
    go into below Account … extra steps"); Brand; Account (Contacts,
    Billing); a tab of several parts is drawn where any is readable;
  - the Activity record (the Record of changes, `tab=activity`) has no tab:
    the rail's Recent activity opens it (View all, `#crmLogAll`), the strip
    then marking none.
  - There is no Work pane. `tab=work` lands in My Work's Months view
    (`view=months&wc=slug`); there is no Reports pane, and `tab=reports`
    lands on Engagements.
- Below 1100 the rail splits. `.rec:not(.cportal) > .rec-rail` is
  `display: contents`, and the blocks take `order`:
  - Next action, the billing gate and Profile come before the tabs.
  - `.rail-after` (Timeline, Details, Recent activity) follows the pane.
- `.rec` is `grid-template-rows: auto 1fr`.
- Overview:
  - One `.ovcard` in the tabs' order: Calls and visits, Contact details,
    Services, Letters; a section whose part the reader may not open is not
    drawn, and one whose read was refused reads Could not load., never empty
    (`ovFailed`, 2026-10-11).
  - Contact details names the primary contact's phone, then a WhatsApp
    number of its own (none, or another than the phone) as its own row,
    the number and the WhatsApp chip (2026-11-10).
  - Built only from what the record has already loaded.
  - Enquired lines are left out.
  - An empty section says so in one line.
- Rail blocks (`.railblock`, `.railtitle` at 15px):
  - Next action: a written `next_action`/`next_at` beats `nextStep()`; a
    written one opens Calls and visits, where it is done. Its date is said
    there alone (the Timeline holds no Next follow up).
  - The billing gate: `.railgate` in red, only while a billing field is
    missing on a record that is not Active; it opens Billing where
    `maySeeBilling()`.
  - Profile: a bar with its missing list.
  - Timeline, Details, Recent activity (the last three `activity_log` rows,
    read once into `state.log`).
  - A block with no data leaves. `paintRail` sets the last rule; never rely on
    `:last-child`.
- Timeline (`railDates`, `journeyOf`):
  - One row per stage (name with a mute date, and the duration). Two tracks,
    never three nowrap cells.
  - The running stage carries `.tl-row.is-now` and the overdue mark.
  - Every stage date and Client since are edited in place
    (`ADspaceAsk.rename`, type date).
  - A stage between the first and the one running now is removed from its
    row's ⋯ (Edit date, Remove, asked first; the band's Full Access, held by
    trigger `clients_stage_log_guard` at Clients Full Access, `stage-log`; the user,
    2026-11-10: a client made Active for days to finish reports, then
    Paused again, counted as a resume): the stages either side that match
    become one from the earlier day, keeping the later reason, and the
    stage clock and the client's reason follow; Undo where it happened puts
    the history back; filed `client.edited` with the stage's reason and
    note (Timeline: Paused from … (Budget: …) removed; … restored).
    - Client since is the first stage's start, opened on its Malaysian day
      (`dayOf`).
    - A stage never begins before the one before it, and no date is in the
      future.
    - One save writes `stage_log`, `stage_since` and `created_at` (a move's
      reason too), only over the row as read (`.eq('updated_at', …)`,
      stamped by trigger `clients_touch`): a move made meanwhile reads "Not
      saved. This changed since it was opened, and has been read again.";
      where only another column moved, the write goes again once
      (2026-10-19).
- Billing required before Active:
  - registered company name (capitals);
  - BRN;
  - billing contact (a select over Contacts: Primary contact · {name} first,
    held empty so it follows the main contact, which `issue_letter` answers
    the same way; another contact chosen stays, and trigger
    `client_contacts_bill_follows` lets go of one that stops being the main
    contact or is removed; 2026-10-13);
  - billing address.
  - Optional: old registration no., TIN, SST no., finance email.
  - Bill in (`clients.bill_sgd`, `2026-10-22-bill-in-rm-or-sgd.sql`; the
    user, 2026-10-22: "follow RM as usual unless and optionally choose to
    have it in S$"): RM / S$ on Billing for a Singapore client alone, RM
    by default, at Clients: Billing Work (`clients_billing_guard`), filed
    from and to; `client_bill_market(market, sgd)` is SG only where both
    hold. `get_portal`, `get_campaign` and `sm_report_snapshot` send
    `bill_market`; `issue_letter` keeps it as the letter's `market`, and
    in `bill_to` the client's market and, billed in RM, `fx_sgd` then in
    force, which the letter reads under its figure in bold (Approximately
    S$ …); `bukku_prepare` sends its currency. The market stays the
    number's, the registration's and Meta's taxes'. A version published
    before reads its market as drawn.
  - Trigger `clients_active_billing` refuses the move into Active while the
    registered name, BRN or billing address is empty or no billing contact
    (chosen, else a live main contact) stands (`active-needs-billing`,
    `2026-10-19-clients-audit-fixes.sql`); a client already Active keeps
    its place.
  - Billing entities (`2026-10-29-billing-entities.sql`, SQL Editor; the
    user, 2026-10-29: "one client several entities, however allow to set
    the main"; a company may bill several brands): `billing_entities` and
    `client_entities` (RLS on, no policy, no grant), one main a client. The
    main entity is the client's billing columns, kept equal both ways by
    trigger (`clients_entity_sync` carries only what a write changed;
    `billing_entity_put` carries an entity to every brand it is the main
    of, a billing contact only to the brand it belongs to), so every reader
    of a client's billing reads its main entity unchanged. A brand's billing
    contact for an entity is its own (`client_entities.bill_contact_id`, one
    of its contacts), else the entity's shared one (any brand's), else its
    live main contact (`entity_contact(p_entity, p_client)`; the letter's
    Attn, the overdue reminder and the pane read it; Bukku's billing person
    stays the shared one); where the entity bills other brands the sheet
    asks Use for every brand this company bills (`#crmBillShared`, ticked
    while the brand has none of its own; `client_entity_contact(p_client,
    p_entity, p_contact, p_every)`, `held` for the shared one Bukku holds),
    and a brand's own Billing sheet writing its contact sets its own
    (`2026-10-31-entity-contact-per-brand.sql`; the user, 2026-10-31: "Could
    be shared or different contact for different brand"). Billing reads the
    main as before (headed Primary billing entity where there are others,
    Also bills naming each other brand, opening its Billing), then Other
    billing entities (`#crmEntities`: its count and Add entity, each one
    row shut by default, its name over its registration no. and billing
    contact, a press opening its facts in place, remembered under
    `client-entities`, one just saved or added open; its ⋯ Edit, Make
    primary, Remove; the user, 2026-10-29: "how long is this"), read on each visit (`client_entities_list`); Add
    entity (`#entAddSheet`, Company) finds one held, every word
    typed in its registered name or the name or Client ID of a brand it
    bills, or its BRN digits (`billing_entities_find`, ten, only those
    billing a client the reader sees, or none; In the portal), a customer
    Bukku holds by every word of its name or its registration no.
    (`bukku-sync` `contacts`, read once as the sheet opens and found on
    the page, eight, held as Overdue invoices are, at Billing Work; In
    Bukku, one the portal holds by BRN left out, one the portal links
    marked Linked in the portal; Bukku not connected is left out, Bukku
    failing said in one line), which Add adds in one press (the user,
    2026-10-30: "just add and pull from Bukku"; `bukku-sync` `adopt`,
    `client_entity_from_bukku`: the entity made from Bukku's details and
    linked to its contact in one transaction, then held, so Bukku holds
    it; a contact the portal already links adds that entity, nothing
    made; `taken` where a supplier holds it; Undo where it happened, none
    for the primary), or opens Billing's sheet as New billing entity (no
    SST on quotes, no currency, no details form), whose Save reads Create
    in Bukku where Bukku answered the sheet: the entity added, then made
    in Bukku (`send` with `guard`), or linked to the customer Bukku holds
    of its registration no., never a second; a refusal leaves it added,
    said on the line, Link to Bukku on its band; Clients: Billing at Work, the
    client in scope (`client_entity_add`, `_save` with `p_expected`,
    `_main`, `_remove`: `no-name`, `bad-email`, `bad-contact`, `stale`,
    `taken`, `main`, `held`: an entity Bukku holds is saved to Bukku, never
    by the portal; the page then reads its band); an entity removed from
    its last client stays reachable to that client's team alone
    (`billing_entities.orphan_of`, `billing_entity_reached`), so Add entity
    finds it again; a BRN held is never made twice, one BRN checked and taken at a time (`brn-taken`, a transaction lock on its digits; the
    question offering that entity), the client's own Billing sheet, Use
    details and a signed quotation's review alike (`clients_entity_sync`,
    `2026-11-04-one-brn-on-billing.sql`), two clients holding one BRN before
    stay two, merged by hand; Make primary and Remove (never the primary) offer
    Undo where they happened; an entity removed from this client and billing
    none is listed on asking (Show n removed entities,
    `client_entities_removed`) with Restore (never asks) and, at Clients:
    Billing Full Access where no letter or Bukku link names it, Delete in its
    ⋯ (`client_entity_delete`, the registered name typed back, no restore;
    `not-removed`, `bills-others`, `bukku`, `on-letter`, `bad-name`;
    `2026-10-31-billing-entity-delete.sql`, the SQL Editor's). Filed
    `client.billing` naming fields alone.
    Console search finds a client by an entity billing it (Billed by …,
    opening Billing). Bill to (`2026-10-29-bill-to.sql`): with two
    entities or more, the Letter of Offer sheet (`#pickBillTo`) and a
    client letter's Issue (`#docBillTo`) ask which, the main first and
    chosen; `issue_letter` takes `p_deal.entity` (an entity of that client,
    `bad-entity`; its name, BRN and address held, `entity-incomplete`) and
    prints its registered name, numbers, address and billing contact,
    keeping `bill_to.entity_id`; none chosen is the main as before. A
    quotation prints no billing. Each entity is its own Bukku contact
    (Bukku, below), and a brand's unpaid invoices and reminders cover every
    entity billing it (Overdue invoices, below).
  - The details form (`2026-10-14-client-details-form.sql`, `js/details.js`;
    the user, 2026-10-14): Billing's Request from client (the user, 2026-10-29; Details form until then, a supplier's Request from supplier) makes a link
    (`client_details_link`, Clients: Billing at Work; Copy link, Preview, the
    ⋯ Reset link and Close link, each asked; `client_details_close` ends the
    open form now, `no-link`, filed, `2026-10-31-client-details-link-closed.sql`)
    to `/details/?k=` with no sign-in, open
    `details_form_days` (14, Settings: Clients, Details form). The client's page (in steps since 2026-11-25: Company, Billing, Billing contact, then Review and submit, and once sent the received page with the client's account manager, `rep` of `client_details_read`, as `quote_website_read` reads it; DESIGN.md §4) reads the
    brand and closing day alone (`client_details_read`) and sends the
    answers once (`client_details_submit`: registered name in capitals, BRN,
    old BRN, TIN, SST no., billing address, finance email, the billing
    contact's salutation, name, mobile and email; refused by field), telling
    the team at Clients: Billing Work whose bands and client scope reach the
    client (kind `client.details`, opening Billing), filed under the actor
    Details form with the typed name in the detail. A move into Active or
    Past ends every link still open (trigger `clients_details_close`), and a
    Past client's link opens nothing (2026-10-22, BE-6). The Active gate's Billing sheet offers it in one line
    (`#crmBillAsk`: Create link, Copy link, or Use details once answered). The answers wait on Billing (`client_details_state`),
    one that differs from what Billing holds reading held → sent (2026-10-20, DTL-1): Use
    details fills the Billing sheet and its own Save takes them in
    (`client_details_used(p_id, p_client)`, refusing another client's form;
    opening Billing forgets an earlier Use details), picking the billing contact the client sent
    where Contacts holds them (email, else the number's last nine digits);
    while Contacts does not, the form keeps showing them, Not in Contacts,
    with Add as contact, before and after Use details, which opens Contacts
    prefilled and makes the contact saved the billing contact. The
    form never writes the record. `client_detail_forms` has RLS on, no
    policy, no grant. An open link offers Copy message (2026-10-31: the
    link in a formal message to the billing contact, else the primary
    contact, with its closing day); answers received carry a ⋯ of Request
    again (asked: they are set aside and a fresh link made,
    `client_details_link`).
  - Billing and Brand read first; Edit opens `#crmBillSheet` /
    `#crmBrandSheet`. The Active gate opens the sheet on the first missing
    field, and its Save, billing then complete, carries on into the move
    (the Client ID asked, the head brought back into view); Cancel forgets
    it (2026-10-20, CLI-6). A Save while that move still lacks a required
    field keeps the sheet on it and the move asked; a Save that changes
    nothing writes and files nothing (2026-10-27, CLI-13).
  - The billing columns (registered name, both registration numbers, TIN,
    SST no., billing contact, finance email, billing address) are withheld
    from the table by column grants. They are read only through
    `client_billing(p_ids)` (`ADspaceAPI.withBilling`): the values at
    Clients: Billing View, the name and address at Documents Work
    (`register_may('client', 'work')`), and `billing_missing` alone at
    Clients View, so the gate still names what is missing; it names a
    missing billing contact too (`bill_contact_id`, as
    `clients_active_billing` holds it), which the record reads until its
    contacts arrive, so the gate never changes under the reader
    (2026-10-27, `tests/billgate.js`).
  - Every read of `clients` names `ADspaceAPI.CLIENT_COLS` or its own list,
    never `*` (refused). A new column is granted by running the CLIENT
    BILLING COLUMNS section again; `script_key` stays withheld with the
    billing columns. The stand-in refuses `*` and every
    billing column, top level or embedded.
- Checklists (`tab=checklists`, `js/checklists.js`,
  `2026-10-15-client-checklists.sql`; the user, 2026-10-15: the team's New
  Client Onboarding and Pre-Advertising Checklists, ver. r1.1-26, once per
  client): one `client_checklists` row a client and kind (RLS on, no
  policy, no grant), the template copied in when it is first written
  (`checklist_template`). The pane lists both, `list=` opening one, on a
  record already open too, and kept in the address (2026-10-27, OVW-12) (its
  Back line and head brought under the bar, never below the fold), read
  first (the user, 2026-10-15: "the checklist is coming back in the wrong
  design"): a head card (title, version, state, Write with AI, Preview PDF
  (a tab opened at the press; PDF on a tight pane), Download beside it (no ⋯; 2026-10-22, CLI-7),
  the facts), then a card a section where a tick is pressed in
  place (its note and who and when under it) and every other answer reads
  as a fact (Not set where empty), a table as a table; no field stands open
  on the pane. A section's Edit (`#ckEditSheet`) opens all its answers in a
  sheet: a tick's Notes and Not applicable, words as a field, a choice as
  chips, a table a row at a time; Save sends only what changed. A platform
  section Not applicable (`client_checklist_set`, Clients Work,
  client scope; `locked`, `bad-item`, `bad-value`, `too-long`; filed
  `client.edited`); the pre-advertising one prefilled from the record (the
  registered name at Clients: Billing View, else the brand; the newest
  quotation at Clients: Services View; the brief's competitors, the
  confirmed Brand analysis's SWOT; `checklist_prefill`), the registered
  name and the quotation never stored: worked out for each reader on every
  read (2026-10-19, audit 3). Mark as prepared
  (`incomplete` with what is left), Sign off by a colleague who neither
  prepared it nor ticked or answered any item (asked; `own`; a tick keeps
  `by_id` beside its name, an answer or note `set_by`, an older tick read
  by its name, `checklist_filled_by`; the read's `filled_by_me` hides the
  button; 2026-10-19, audit 13), Send back, and Reopen at Manage (asked; the signed copy kept in
  `history`) through `client_checklist_step`; signed, it locks and ticks
  the month's check of that key (`ready`), and Reopen unticks it. A month's
  check is never ticked by hand (`ops_engagement_set_check` refuses
  `use-checklist`); My Work shows it with Open on the client's checklist.
  Download draws its PDF on the plain Internal use only page (DESIGN.md §2, Print). The
  Pre-Advertising Checklist is ver. r1.3-26 (`2026-10-15-checklist-r13.sql`;
  a checklist started before keeps its template): Campaign Details asks
  Primary Destination and Monthly Budget; Meta Campaign Setup holds
  Campaign Setup, a table of Item, Details, Audience, CTA and A/Spend (kind
  `table`, twelve rows, 400 a cell, Add row and a row's ×, saved whole);
  Country, Ad Re-Targeting and Tracking (Pixel / Analytics Connection, Lead
  Destination, Tracking Relevance, Ads Reporting Schedule) are written
  answers, as the team writes them (the user's three checklists,
  2026-10-15). `checklist-draft` writes to that standard (`SYSTEM`: short
  working notes, approx., TBC, → to where a button leads, ad sets funded
  in order with MONTH 2+ / ON HOLD, the lead estimate, Budget note); the
  PDF draws → in the Chinese face, which holds it.
  Write with AI on it (Clients: Checklists Work, an open checklist; the user, 2026-10-15)
  asks up front the monthly ad budget, the objective, where the ads send
  people, the ad account and notes (kept under
  `adspace-checklist-inputs:{client id}`); with no confirmed Brand
  analysis the same press runs one first (the user, 2026-10-15: never Brand
  first and back again), read in `#ckBaSheet` and confirmed there with the
  declaration (filling the brief), then `checklist-draft` reads the
  confirmed Brand analysis (`no-analysis` without one), the Ad benchmarks
  and the linked Meta accounts and proposes every field but the ticks,
  following the playbook's Meta rules (the client's website sent as
  whether it has one, never its address); nothing is written until the
  colleague keeps the ticked proposals in `#ckAiSheet` (what a field holds
  now said under it), declares them read (`ADspaceConfirm.ai.declare`) and
  each is saved as if typed, Undo where it happened. Its own count
  (`ai_checklist_claim`: `checklist` 10), priced and
  set on AI usage; the client's name goes as {brand}. Not signed off on
  an Active client, unless the month marks it Not needed, is a Dashboard
  Needs attention row (`client_checklists_due`), only where it was started
  in the portal or the client first became Active from 15 Oct 2026 (MYT):
  one onboarded before was checked on paper (the user, 2026-10-19;
  `2026-10-19-checklists-from-portal-onboarding.sql`). A client's passwords are
  never kept: the credentials item is a tick. The templates are edited in
  the migration, not in Settings, for now.
- The Brand tab (2026-11-22; the user approved the restructure) is five
  `rec-part` cards in working order (`paintBrandRead`): Brand profile (Logo,
  Website, Office phone; Edit), Social accounts (`#crmMetaRead`: Instagram,
  Facebook, TikTok, rednote, each its pen in place, Instagram and Facebook
  with Linked in Meta: the account; Ad accounts; Edit Meta accounts), Brand
  analysis (`#crmAnalysis`), Content brief (`#crmBrandBrief`: Audience and
  pillars, Voice and references with Other notes, each its own Edit; a part
  equal to what a confirmed version fills reads From Brand analysis, version
  n, worked out on each paint, never stored), White label (`#crmWlBrands`,
  drawn while on or at Reports: White label Work: the switch at the press
  with Undo, turned on with no wide logo opening the sheet). One sheet
  (`#crmBrandSheet`, `openBrandSheet(mode)`) shows one part's fields and
  sends only what moved; nothing moved writes and files nothing. Over the
  parts, `#crmBrandReady` reads Write with AI ready or not ready with what is
  still needed, from the brief and the versions already read (as
  `ai_brand_ready` answers), never a request of its own. Brand notes reads
  Other notes (the user's D3); the column stays `brand_notes`. Linking an
  Instagram account or a Page in Meta fills the client's empty handle with
  its username (`@` and letters, digits, `.` and `_` alone) or the Page's
  name, filed Filled from Meta (`handlesFromMeta`, D1); a typed handle is
  never replaced. An Instagram or Facebook row with no link in Meta reads
  Not linked in Meta. The handle is typed by hand. (the user, 2026-11-22:
  filled from Meta only where the system user reaches the account).
- Brand analysis fed from what the portal holds (2026-11-22, release B):
  `brand-analysis` reads, as the caller, the latest standing quotation
  (plan, platforms, monthly advertising budget, term), the client's last 20
  change requests and 20 approved captions in Content Review, and the last
  five notes of calls and visits (D2: no contact's name, numbers and emails
  masked), with every handle and the linked Meta accounts' names; it keeps
  what it was told or worked out with the version (`basis.inputs`: budget,
  objective, ad account, notes, `derived`: the budget from the quotation,
  the objective from the ad spend, the ad account from whether it spent),
  read under the version as Ad plan. Run analysis opens on this browser's
  answers, else the last version's, else the quotation's budget, each said
  under its field (D4). Where the name matches more than one business and
  the record does not settle it, the function saves nothing, counts nothing
  and answers `ambiguous` with up to five candidates; the page asks Choose
  the brand and runs again with `choice`, which the model analyses alone
  (the user, 2026-11-22: never guess the brand).
- Meta links (`2026-10-08-meta-links.sql`, `meta_links`, RLS on, no
  policy, no grant): a client, and each white-label brand, links ad accounts
  (up to 20), one Facebook Page and one Instagram account, each Meta's id and
  name, picked in `#crmMetaSheet` from `meta-import` `assets` (Clients: Brand at
  Work), never typed; a link Meta no longer shows stays offered. Read first
  on Social accounts (`#crmMetaRead`, Edit Meta accounts at Clients Work; a brand's from its
  ⋯, Meta accounts); `meta_links_save` (Clients Work, the client in scope at
  Work, `bad-brand`, `bad-asset`; writes through insert on conflict, so two
  first saves at once both stand, 2026-10-19) files `client.brand` from and
  to, a brand's under its name; `meta_links_list` at Reports or Clients View.
- The content brief (`clients.brief`, `2026-10-10-client-brief.sql`; the
  user, 2026-10-09: "content not interesting"): one object of short texts
  (audience, pains, pillars, tone, avoid, competitors, hooks; 8,000
  characters in all), read with the record alone, read first on the Brand
  tab (Content brief) and edited a part at a time (Audience and pillars;
  Voice and references), sent only where a part changed, filed
  `client.brand` by the parts' names. Write with AI reads it and the brand
  notes for captions and scripts, masked as the rest (`{brand}`,
  `{handle}`); never a competitor named back.
- Write with AI waits for the brand (`ai_brand_ready(p_client)`,
  `2026-10-12-ai-needs-the-brand.sql`; the user, 2026-10-12): a caption or a
  script needs the brief's Audience, Content pillars and Tone of voice and a
  confirmed Brand analysis; reports are not held. The press asks nothing
  until then: one `.msg.warn` line under the button names what is missing,
  with Open Brand where the colleague reads Clients
  (`ADspaceAdmin.brandGate`, `brandSay`), and `caption-draft` and
  `script-draft` refuse the same (`no-brief` with `missing`,
  `no-analysis`) before a use is counted. Run analysis asks no brief
  (2026-10-15): it needs something to read, the website, a handle or a
  linked Meta account (`no-source`), and writes the brief itself
  (`analysis.brief`); confirming a version fills each empty part of the
  brief from it (`2026-10-15-analysis-fills-brief.sql`, at Clients Work in
  scope; a part already written is never replaced; filed `client.brand`,
  said on the Undo line).
- Brand analysis (`2026-10-10-brand-analysis.sql`, `brand-analysis`; the
  user, 2026-10-10: "deep analysis of this clients … target audiences,
  SWOTs, advantages disadvantages, ads targetting"; "anyone could run it"):
  the Brand tab's third part (`#crmAnalysis`), Run analysis then Run
  again (the AI mark; asks first: what it reads, analyses left today, notes
  kept under `adspace-analysis-notes:{client id}`), for any colleague at
  Clients: Brand View on a client in scope. It reads as the caller the record
  (brief, notes, services), published reports, My Work's post results and,
  where `meta_checks_on()` and the client links Meta, six months of
  Instagram and Facebook posts, Instagram followers by age, gender and city
  and the ad accounts by objective and age, with Claude's web search
  (`web_search_20260209`, eight at most) on the brand's own pages and its
  competitors'; sections Brand positioning, Target audiences, SWOT,
  Content, Ad targeting, Sources (pages the search returned only), "A
  starting hypothesis to test" where the client has no reports, results or
  Meta posts. The team's client analysis playbook (2026-10-15): Run
  analysis asks up front a monthly ad budget, the main objective and the
  ad account (New, Mature; kept in this browser under
  `adspace-analysis-inputs:{client id}`), never a question back; the
  research checks the entity and its parent group first, labels each fact
  Official, Listing or Third party and marks one its sources disagree on To
  confirm, places a business by what buyers know, and maps competitors
  (direct, indirect, legacy, disruptor); a version holding them leads with
  What it is, What works and what is weak (trust leaks), Where ADspace fits
  (channels first, next, later; what to fix before paid traffic; the
  commercial angle), and ends with To confirm with the client and Next
  question, Ad targeting adding Budget realism against the Ad benchmarks
  (sixteen Business settings, `bench_*`, `2026-10-15-ad-benchmarks.sql`:
  cost per result by kind, impressions, the ad spend share of a budget
  83.75%, RM 30 a day an ad set), read by the function as the caller; an
  earlier version reads as it was. **The brand name goes to Claude for this function alone (the
  user, 2026-10-10, for the web research); never a contact, and an email or
  number typed into the words is masked.** `brand_analyses` (RLS on, no
  policy, no grant) keeps every run as the next version
  (`brand_analysis_save`, filed `client.brand`), listed newest first with
  who ran it (`brand_analyses_list`); a draft until Confirm asks the AI
  declaration (`brand_analysis_confirm`, Undo, then Withdraw confirmation in
  the ⋯), and a version's ⋯ Delete at Clients: Brand Full Access (asked, no
  restore; `brand_analysis_delete`, refused `in-use` for the latest
  confirmed version; `2026-10-31-brand-analysis-version-delete.sql`, the SQL
  Editor's). Only the latest confirmed one reaches Write with AI
  (`brand_analysis_brief`: positioning, audiences' pains and motivations,
  pillars) for captions, scripts and report drafts, masked as the rest.
  Counted apart (`ai_analysis_claim`: `analysis` 3),
  its web searches kept (`ai_drafts.web_searches`) and priced at
  `ai_price_search` (US$10 a thousand, a Business setting). The response is
  streamed with a space every 8 seconds while it runs (140 seconds at most).
- A restricted account (`2026-10-10-account-restricted.sql`; the user: "account
  restricted"): `clients.restricted_platform` (Instagram, Facebook, TikTok,
  rednote, Other account), `restricted_since` and `restricted_note`, all or
  none, read with the record alone. The record's ⋯ Mark restricted
  (Clients Work; asks the platform, since when, a note) and the rail's red
  block (`#crmRestrict`, `.railgate.is-restricted`) with Clear (never asks,
  Undo where it happened), each filed `client.edited` from and to. The
  Dashboard's Clients tab lists them (Restricted accounts, the longest first).
- VIC, a Very Important Client (`2026-10-15-vic-clients.sql`; the user,
  2026-10-15, "VIC … Very Important Client not Person"): internal alone,
  never on a client page, link page or PDF. `clients.vic_at` (the day it
  became VIC), `vic_by`, `vic_note` (300) are written only by
  `client_vic_set(p_client, p_on, p_note, p_since)` (`clients.vic` at Work,
  the client in scope at View; `denied`, `not-found`, `too-long`,
  `bad-date`; filed `client.edited` from and to); trigger
  `clients_vic_guard` refuses any other write (`vic-function`). The console
  reads `vic_clients()` once beside `me()` and every screen asks
  `ADspaceAdmin.vic(id)`, never a read of its own. One tag
  (`ADspaceAdmin.vicTag(id, inRow)`, `.chip-vic`, the crown and VIC in
  gold): a button opening `#vicPop` (Very Important Client (VIC); prompt,
  priority attention; issues count double in performance reviews; the
  note; VIC since {day} · set by {name}) on a desk's hover, a press or the
  keyboard's focus, docked on a phone, Escape first; inside a row that is
  one button it is part of that button and shows its card on hover alone.
  Where it shows: the Clients list (the logo's gold ring with the crown on
  it, `ADspaceAdmin.vicBadge`, its card on a desk's hover, the name
  carrying no tag; a VICs view drawn while any is held), the record head (tag and ring; the ⋯'s
  Mark as VIC, asking VIC since and a note, or Remove VIC, never asked,
  Undo where it happened; VIC since under Key dates, its pen at the part),
  Content Review's list (the logo ringed with the crown, as the Clients
  list) and client head, My Work's rows, board cards and
  task card (a VIC client's work leads each band of the day axis, Urgent
  delivery a band above it), Waiting for you (VIC rows first, the tile ringed in gold with the
  crown on its corner in place of the tag), the
  Dashboard's Needs attention (VIC first among equals), the Creator
  Campaigns, Reports and Video Scripts lists, and console search. A notice
  about a VIC client's work is titled "VIC · …" (trigger
  `ops_notifications_vic`), the bell and the push alike. No priority is
  set by it.
- One set of handles and one logo per client:
  - Brand alone edits `handle_*` and `logo_url` (Content Review's sheet
    keeps the access code alone, 2026-10-29); its logo field has Upload
    (`wireLogoUpload`): the picture is drawn down
    to 800px in its own format and stored under the client's folder by
    `sign-upload`, so the address never expires as a Facebook picture's does.
  - `social_*` is backfilled by `handle_of()` (a bare handle, or a URL's last
    segment; nothing where that segment is a route) and never written.
  - `profileUrl()` derives the links.
  - Content Review re-reads the row on opening a client, so its head shows
    the handles and logo as Brand left them.
- Contacts:
  - A table, with `.plink` reach links.
  - Salutation (`client_contacts.salutation`, `2026-10-09-contact-salutation.sql`;
    the user, 2026-10-09): a select before the name (Mr, Ms, Mrs, Mdm, Dr,
    Prof, Dato', Datin, Datuk, Dato' Sri, Datin Sri, Tan Sri, Puan Sri, Tun,
    Tuan, Puan, Encik, Cik, or None), shown before the name on the row and
    filed from and to. `contact_greeting(salutation, name)` greets with the
    salutation and the whole name (the salutation said once), else the whole
    name, never its first word (a creator and a colleague alike; 2026-11-11,
    "Kai Sin but Kai only"; `2026-11-11-greeting-by-whole-name.sql`). A name after its
    salutation says one salutation: one the name opens on gives way to the
    one set (`ADspaceWords.person` on every page, `contact_named` in SQL,
    `2026-10-29-salutation-said-once.sql`; 2026-10-29: Mrs Ms Agnes Ang).
  - WhatsApp: a username field with `@` prefilled (letters, digits, `.` and `_`;
    a pasted `wa.me/@name` taken whole). `client_contacts.whatsapp` holds
    `@name` or the number: the field opens on the stored number where it is
    no username, is sent only where it changed, and digits typed into it
    are stored as a number (2026-10-19).
  - The main contact changes in one transaction
    (`client_contact_make_primary`, Clients: Contacts at Work, in scope), so
    a refused change leaves the old one.
  - One builder for every wa.me link, `ADspaceAPI.waNumber` (the console,
    the client portal, the creator's page, the namecard), reading a number
    as `wa_number` does in SQL (WhatsApp, below).
  - Remove is soft, then Delete permanently at Manage.
  - A contact with a number offers Send on WhatsApp in its ⋯
    (2026-10-31): the composer (`purpose` message) opened on that contact
    (`contactId`); nothing goes until its Send.
- Portal access is one switch per contact (Enable / Revoke in the ⋯, with
  Undo), shown as Portal access after its green dot.
  - Enabling opens a sheet with **Send invitation email unticked**; a move
    into Active asks it of the main contact (Give client portal access?),
    the invitation ticked, never switched on by itself (2026-10-26).
  - Send invitation stays in the ⋯. Undo emails nobody.
- Services:
  - Quantity × rate × months from a start date; neither below zero
    (`client_services_rate_check`, `client_services_qty_check`; the sheet
    refuses it in words, the field taking focus).
  - Enquired / To quote / Confirmed. Confirmed comes from a verified signed
    letter (`verify_letter`) or the admin's reasoned override alone: the
    sheet never offers it (a confirmed line reads its state), and trigger
    `client_services_confirm_guard` refuses a page that inserts or moves a
    line into it (`confirm-needs-letter`; `2026-10-10-service-confirm-guard.sql`,
    audit S1).
  - Remove is soft with Undo; a removed line is listed on asking with
    Restore (`client.service_restored`) and, where no letter quoted it,
    Delete at Clients: Services Full Access (asked, `client.service_deleted`;
    2026-10-13); a line a letter quoted stays (`client_document_services`
    restricts it) and offers no Delete.
  - `detail` and `min_months` are seeded from the rate card and stay editable.
  - A line is chosen, never preselected (Choose a service), opens on To
    quote for a client at Proposal sent or Active, and takes no term where
    its unit is not by the month; for a client billed in S$ the card's RM
    is turned at `fx_sgd` to the cent and the rate reads Rate (S$), left
    empty while no rate is set; its term percentage is the live version's,
    as a quotation's (2026-10-22, SL-1, SL-3, SL-5 to SL-7).
- The term adjustment is a tick with a percentage (`term_pct`, stored whether
  the tick is on or not).
  - Prefilled from `termPct(months, at)`: a term takes the longest commitment it
    has reached (the user, 2026-11-17): Under 3 months (1 and 2), then the
    3-, 6-, 12-, 18- and 24-month commitments (3 to 5, 6 to 11, 12 to 17,
    18 to 23, 24 and more; `quote_term_pct`, `termPct`, the Rate Card's
    3 months reading `term_4_5`), each percentage a setting (`term_1_3` 25,
    `term_4_5` 15, `term_6_11` 0, `term_12_23` −5, `term_18_23` (12's where it has no
    row of its own, page and `quote_term_pct` alike, never a seed of the page's), `term_24` −10), Tax and
    terms at `team.settings` alone, 0 for none; a quotation takes them, and
    SST, as in force today over the live version's (`quote_card`,
    `2026-11-06-quotations-priced-on-todays-terms.sql`; the user,
    2026-11-06: a setting changed applies at once, never waiting for a
    publish); a changed term or SST is a change the card's Publish counts,
    Review listing it under Tax and terms.
  - The field follows the card only while it still holds the card's figure
    (`svPctCard`).
  - `rateFor(rate, months, adjust, pct)`: a percentage bills the rate × pct;
    `null` uses the older factor table; only an explicit `false` turns it off.
    Rounded to the cent where charged.
  - `issue_letter` snapshots it and `get_portal` sends it.
- Calls and visits carry next actions and an Undo (Done or Reopen on the
  row; Edit and Remove, or Restore and Delete, in the row's ⋯), and who
  logged it by name (`by_whom`; an older entry's sign-in email reads as
  the active colleague's name, else nothing; 2026-10-15); a removed entry is listed
  on asking with Restore and Delete (Clients: Calls at Manage, asked first,
  `client.touch_deleted`). A Meeting entry
  (`2026-10-05-meetings-outside-a-month.sql`) takes a time (MYT), a length
  (15 to 240) and a Meet, Zoom or Teams link; while ahead with no link it
  offers Create Google Meet (`meet-create` with `touchId`, Clients: Calls
  Work), a moved time moves the event and an entry no longer a meeting
  takes it off; the client's Meetings lists it as Meeting (time, length,
  link while ahead), never its summary. The link is the `.plink` address.
  A meeting ahead offers Message to client, Show and Copy (2026-10-31):
  the team's Meeting message filled from it (`ADspaceOps.meetingMessage`,
  the one builder the month's card uses too; no content month, so no
  agenda line), copied to paste into the client's WhatsApp group.
- Automatic emails and Automatic WhatsApp (`2026-11-10-automatic-sends-switch.sql`;
  the user, 2026-11-10: "automatic only"): two switches in Settings,
  Messages (`auto_email_on`, `auto_whatsapp_on`, seeded On; `auto_send_set`,
  `team.settings`, filed). Off, the creator emails (`creator_mail_queue`,
  `creator_mail_job`) are kept as Not sent (`off: Automatic emails are
  off.`) and never sent later, and `wa_enqueue` queues no colleague
  reminder or creator booking message; the claim holds the same (`wa_claim`,
  `creator_mail_claim`), so one queued before the switch moved, or put back
  after an outage, is failed Not sent (audit 2026-11-11); whatever a colleague presses goes
  as before. A new automatic send asks `auto_send_on(kind)`.
- Nothing reaches a client by itself (the user, 2026-10-31): every
  client-facing send is a colleague's press, and most go into the client's
  WhatsApp group, which no API can post to, so a record offers its message
  to copy (Copy message) beside any WhatsApp template send.
- Requests (Request · Fee · State · ⋯):
  - Requested → Reviewing → Approved / Declined → Applied; Withdrawn is a chip.
  - Reply sets a fee and a reply the client reads.
  - Approval never edits a service line.
  - A reply or a move is written only over the request as it was read
    (`.eq('updated_at', …)`, stamped by `client_requests_touch`): one the
    client withdrew or a colleague answered meanwhile reads "Not saved. This
    request changed since it was opened, and has been read again." and the
    list is read again (audit C2, 2026-10-10).
  - Add request (`#crmAddRequest`, `#crmReqAddBox`; Clients: Requests at
    Work; the user, 2026-10-31): a request the client made on a call or in
    a chat, its kind as a segment, the confirmed line where the kind needs
    one, Requested by (a contact of the client or Not named) and a note
    (asked unless Cancel), kept as the colleague's
    (`client_request_add(p_client, p_kind, p_service, p_contact, p_note,
    p_idem)`, the client in scope at Work, the portal's own refusals with
    `no-service` and `bad-contact`, one key a sheet, filed
    `request.added`; `client_requests.recorded_by`); its row reads Recorded
    by {colleague} (for {contact}) where a client's reads its contact. The
    section shows on an Active or Paused client to a colleague at Work.
    Each row's ⋯ holds Delete at Requests Full Access (asked, no restore;
    `client_request_delete`, the client in scope at Manage, filed
    `request.deleted`).
- Engagements (`js/engage.js`, `tab=engagements`; the user, 2026-10-09:
  "one less tab to monitor"): the client's work by content month, its
  reports included. The tab is drawn for an Active, Paused or Past client,
  or one holding anything in it (a lead's waits for the answer, and its
  address falls back to Overview). The head holds Open Content Review /
  Enable Content Review, New campaign and New month (My Work at Work;
  2026-10-31: opens My Work's Months on the client, `new=month`, with the
  New month sheet), each behind its own check, while the client is Active.
  - A card a month (`ADspaceGroup.section`, route `client-months`), newest
    first: a month from today's on open, an older one shut until opened and
    remembered; a month starting on its `start_day` states its span on the
    heading, and the heading counts the month's overdue tasks in red, late by
    My Work's rule (`ops_engagement_counts` `late`, `ops_task_late`). A month
    is drawn only where the reader may see something in it.
  - A row a thing (`.cmonth-row`: the section's rail glyph on a tonal tile,
    the name over its facts, the state, the chevron), in the rail's order:
    Content (My Work View: `n of N done` as the month line reads it, red with
    an overdue task, Completed, Cancelled, No tasks; Report due while ahead;
    opens the client's Months view), each Content Review set (`review.sets`
    View; Published or Draft), the month's Video Scripts as one row
    (`scripts` View; `n scripts · n published`, Published once all are;
    opens the month's scripts), each creator campaign (`campaigns.campaigns`
    View; `W.campState`), each report (Reports View: Draft, In review,
    Confirmed, Published with Sent {day} or Not sent, On request and White
    label as chips; opens the report). A colleague at Clients View without
    Reports reads the finished reports alone (`sm_client_reports`), each
    with Download (`ADspaceReports.clientFile`, `sm_report_file`). A row
    opens its record as search does (the address, then the section).
  - Filed by content month: a report by the month whose span holds its last
    day (as `sm_report_gate` finds it), a set and a campaign by the day they
    were made (MYT), a script by its `period`; with no month holding the day,
    the calendar month. A reader of Reports without My Work takes the spans
    from `sm_report_months`.
  - Each block asks its `may()` before it reads and is read once for the
    client in one request (never one a month or a row): on opening the
    record, on entering it again and on a visit to the pane; a repaint reads
    nothing. A refused read is `failLine` for that block alone, above the
    months, with Try again. Nothing at all reads No engagements.
  - The month's invoice (2026-11-22): at My Work View and Clients: Billing
    View, each content month already begun and not cancelled ends with a
    row an invoice the night found in Bukku for it (`ops_month_invoices_of`,
    the copy My Work's month reads; never a Bukku read here): Invoice over
    its number, amount and date, Paid or Unpaid as the dot and its word,
    Open in Bukku a `.btn-sm` at its own width; Not invoiced with the day it
    was checked where none was found. A month not yet checked, or a client
    with no Bukku contact, draws none. Below Billing View nothing is asked
    and the function refuses `denied`.
- Delete client:
  - in the record's ⋯, as a sheet counting from the loaded record;
  - the name typed back, plus the delete code where `delete_code_set()`;
  - `delete_client` re-checks at the press (an active colleague at Clients
    Manage, `Not allowed`) and files `client.deleted`
    itself, in the transaction that deletes (audit R1); the page files
    nothing.
  - Paused and Past are the everyday exits.
- Person in charge (`owner` holds a name as text):
  - Changed from one colleague to another only at Clients Full Access, or by
    Team Full Access carrying a stand-down or a rename (`clients_owner_guard`,
    `owner-change`). A lead is sold, not run: during the lead stages only
    Sales by is set, and Person in charge is the operations colleague named
    once the client is near confirmed (the user, 2026-11-06). Take lead
    (`#crmTake`, under the name on the record head, at its own width) makes
    the colleague Sales by on a lead nobody sells or runs, at Leads Work
    (`clients_sales_by_guard`, `2026-11-06-take-lead-as-sales-by.sql`),
    filed `Sales by: not set → name`; the head's meta reads Sales by while
    no Person in charge is set, and /quote/ names the Sales by colleague as
    the prospect's representative until a Person in charge is set.
  - The stage select greys a stage whose band the colleague cannot work, and
    New lead needs `clients.leads:work`.
  - Standing a colleague down, or Delete, asks who takes each kind of their
    live work (Team, below); the clients and open campaigns they are person
    in charge of are two of the kinds. Keep is first, and only active
    colleagues are offered.
  - The move takes `.select('id')` and files `client.edited` /
    `campaign.edited`.
  - A completed campaign keeps who ran it.
  - A rename carries onto every record.
  - Select clients (the bar's ⋯, `clients:manage`): each row shown becomes
    its tick inside the name cell (`label.client-row.is-picking`, the
    columns unmoved), a press anywhere on it ticking it; the bar
    (`#crmBulk`: a tick for every client shown, `n selected`, Done) offers
    Reassign, asking one colleague, moving each ticked client
    not already theirs through the same write (`.select('id')`, the guard
    re-checking, filed `client.edited` from and to), naming a refusal
    against its client, with Undo where it happened putting back each
    client's own.

- Every write to a client goes through `writeClient(id, patch[, since])`:
  it asks `id, updated_at` back and every copy the page holds takes the new
  stamp, so the next Edit is never refused as changed by someone else; a
  write built from the copy read at open (Edit, the Brand sheet's content
  brief) passes `since` and a refusal reads `ADspaceWords.line.stale`
  through `staleClient` (review 2026-11-24, `tests/editstamps.js`).

## Components

Moved from DESIGN.md §4 on 2026-11-22.

| Need | Component |
|---|---|
| What clients owe, past its date, and a reminder by email (Clients' Overdue invoices) | `#odView` (`js/invoices.js`) under Clients' view strip (`#crmViews`, a section's switch at its own width at a desk, on a phone the column's width, two views equal halves, three (with Payments, for Billing Full control) sharing what is spare, each word whole): the tallies (Overdue, then each age, a currency a line, a mute em dash for none; five across while they fit, else Overdue takes the row and the ages run four across, two when tight, `data-narrow` 760), then an `ADspaceGroup` card for each age with its totals at the right of its head; a `.inv-row` the tick (sending only), the client over the invoice and its instalment, the overdue amount (of its balance under it), the due date, the days in red, the last reminder as `.chip-state` with Open in Bukku; on a narrow pane three lines: the client and the amount; the invoice with Due {date} (its parts never broken) and the days with overdue in red; the last reminder and Open in Bukku at the right edge. Review and send (`#odSheet`, an 880px `.formsheet`): the clients at the left (`.inv-rv-row`, the chosen `--line-soft`), the email at the right on its own light page (`.inv-mail`, the email's own palette in both themes), To, Copy (a tick) and Subject as `.ovfacts` with Edit, then Sent before as a table of four (When, Channel, Sent by, Status); on a phone the list over the email, the Edit under the facts; amounts in the words hold their sign (a no-break space); a client's own (Billing, `#odClient`) is a `.readgroup` of `.od-crow`s (number and instalment, due and days or Not due, the amount, the last reminder's chip), each company billing the client under its name where there are several (`.od-co`, 12/600 mute), over Reminders sent as the same four-column table, Send reminder at the head's right |
| The Clients list over its bands (v3, 2026-11-12) | `#crmTiles`, four `.ovw-kpi.crm-tile`s across (two narrow) above the bands, each from the clients already read: Leads in hand (n proposals sent; a `--sunk` foot in red words naming those past their follow-up time), New leads this month, Active clients (n paused) and, at My Work View, Late work this month (across n clients). A client's late work this month (`ops_engagement_counts`, read once a visit) is a red `.tone.is-danger` tag after its name; Person in charge and Sales by each lead with the colleague's disc (`ADspaceAdmin.avatar`, left off narrow) |
| A client billed by several companies (billing entities) | Billing's read groups for the main entity (its first heading Primary billing entity once there are others; Also bills as `.linkbtn`s), the Bukku band, then Other billing entities as a read group (its count as a `.tab-n`, Add entity `.btn-sm` at the right, None. while empty) and a fold an entity (`.ent-fold`, a `--line-soft` hairline over each: the registered name in the `fsec-h` face over its registration no. and billing contact in 12.5 mute, the chevron and a ⋯ of Edit, Make primary and Remove at the right edge; open, its facts under it, then its own Bukku band 12 under (`.ent-bk`), and the summary gone); Add entity a `.formsheet` whose search answers as shaded radio rows (Bukku's customers read once as it opens and found as the person types; one picked is added and linked at Add) (`.ent-pick`, the chosen ringed in ink) under 12/600 mute group labels (`.ent-picks-h`: In the portal, In Bukku, Not listed), New entity last |
| A read group with its own act (Brand: Meta) | `.readgroup` > `.readgroup-head` (the `fsec-h` title, then a `.btn-sm` with its glyph at the right edge) over its `dl.ovfacts`; its sheet holds a ticked list (`.meta-accs`, its own scroll past 40dvh) and the selects |
| An AI analysis read first (a client's Brand analysis) | `.readgroup.ba`: the head's acts at the right (`.ba-acts`: blue Confirm while a draft, then Run analysis / Run again with the AI mark, a ⋯ once confirmed), State, Version and Read from as `.ovfacts` (always open), then a fold a section (`.ba-fold`: a hairline over it, the `fsec-h` title over its summary line in 12.5 mute cut to one line, the chevron at the right edge; shut, remembered per client, Brand positioning open on a draft), points as `.ba-list`, sources as `.plink`s and other versions as `.linkbtn`s each in a fold of their own; a line of parts holds each part whole (`.ba-part`) |
| A client's checklist (`js/checklists.js`) | Read first: `.ovcard.ck-head` (title over version, `.ck-ctl` the state, Write with AI, Preview PDF and Download beside it (no ⋯), then `.ovfacts`), a `.ck-sec` card a section (its `fsec-h`, Edit with the pen at the right, a platform's Not applicable beside it): ticks as `.ck-row.is-tick` pressed in place, answers as `dl.ovfacts`, a table read as `.ck-table.is-read`; Edit is `#ckEditSheet`, never a field open on the pane. A sheet's table stacks a row a `--sunk` card under `data-narrow="560"`, never cells splitting a word |
