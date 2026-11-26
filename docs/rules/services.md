<!-- triggers: js/quotes.js js/quotepdf.js js/ratecardpdf.js js/quote.js quote/ supabase/functions/quote-request js/money.js -->
# Services (the rate card)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- Two tables, Services and Add-ons, with categories that carry their count.
  Admins edit; everyone reads. Rates are in RM. At Services Full Access the
  price on a line is changed where it is read (`ADspaceAsk.rename`, empty is
  On quote), into the draft as the sheet's Save is; a rate below nought
  stays open with its refusal, a database refusal said on the row
  (2026-10-27, SVC-10).
- `detail` (one inclusion per line) and `min_months` seed a client's line.
- A category's order is `position`, then slug (`2026-11-25-rate-card-line-order.sql`):
  a line added, or moved to another category by its Edit, goes after that
  category's last (`services_place`); each line's ⋯ offers Move up and Move
  down after Edit (Services Full Access, only where the move stays in its
  category and state), through `rate_card_move`, refused `stale` over an
  order the page does not hold, Undo under the category; the draft's review
  compares a line's rank in its category (Order changed), never the figure.
- A line's key is its slug, made from its name: a name already on the card
  is refused as such ("A service with this name is already on the Rate Card."),
  the SKU's own clash as the SKU's; Set inactive, Save and Delete repaint
  the list from the row as written, a new line reading the card alone
  (2026-10-22, SVC2-1, SVC2-7).
- A line carries its Bukku item code (`services.sku`,
  `2026-10-15-service-sku.sql`; the user, 2026-10-15): typed in the line's
  sheet beside Category (letters, digits and . _ / -, 40 at most,
  optional), one line each ignoring case (`services_sku_idx`, "That SKU is
  already on another line."), shown under the name in the token face
  (`.svc-sku`) and found by the Services search and console search; filed
  from and to; not part of `rate_card_draft`, so it never marks the card
  Changed. Shown on the rate card alone, never on a quotation, letter or
  PDF.
- A line leaves by Set inactive, then Delete permanently (Manage). The delete is
  refused while any live `client_services` line names the slug, and the refusal
  says how many.
- The schema seeds the whole card once, into an empty table, and `detail` only
  where it is null. A new service is added on the page.
- Versions (`2026-10-13-rate-card-versions.sql`; the user, 2026-10-13: the
  card "should run based on versioning"): the lines and the card's words
  (`rate_card_text`, a block a key, changed only by `rate_card_text_save`)
  are a draft; Publish (`rate_card_publish(p_version, p_valid_until,
  p_note)`, Services Full Access; `bad-version`, `version-taken`,
  `bad-date`, `no-change`; filed `service.published`) keeps the lines, the
  words, SST and the term percentages whole in `rate_card_versions`, and
  `rate_card_current()` answers the latest (at Services or Clients: Services
  View). A client's line, a quote and the
  export are priced from the live version, never the draft; with none
  published, the card as it stands. The page: one command bar holding the
  search (Rate card alone), the version line (Live v.{n} · valid until,
  Review n changes, Publish) and the acts (Download,
  Add service on Rate card alone; on a phone the line under the marks where
  a search stands, else beside the ⋯; the user, 2026-10-14), then Rate card,
  Versions (`tab=`; an older `tab=words` opens the card); the wording is
  edited from Settings' Templates, Rate card wording (`#rcwListSheet`,
  `ADspaceCRM.openWording`, 2026-10-29), each block's pen opening
  `#rcwBox` and its Save or Cancel back to the list, and still published
  with the card here; a line or block the draft changed reads
  Changed (or New). A line the live version still offers is not deleted.
  Review n changes (`#svcReview`, a tonal toggle, `aria-pressed`; equal
  halves with Publish on a phone; the user, 2026-10-22: "approve") shows
  only what the draft holds that the live version does not: the lines
  changed, each naming what moved from and to (`ADspaceRecords.changes`),
  the lines removed, the blocks of wording changed, under Showing the n
  changes not published. with Show the whole Rate Card, the search set aside;
  Publish's question lists the same, five, then and n more (SVC2-M1).
- A block of wording is edited as the card prints it (`#rcwBox`; the user,
  2026-10-13: one box of lines read "ugly and untidy unstructured"): a list
  as numbered points (a field each, Add point, Move up, Remove), a table a
  row at a time under the columns its label names (Add row; one row fixed
  where the card prints one), a sentence as one field; saved as the lines
  the PDF reads. On a phone a point's number and acts share its first line.
- Download on the version line, and on each version's row on Versions (the
  version read whole at the press) (`js/ratecardpdf.js`,
  `ADspaceRateCardPdf.draw`; the user, 2026-10-13: the card in "their exact
  format", FOR INTERNAL USE kept) draws the live version as the team's six
  A4 pages, never stored: the cover, Ala Carté, Social Media Services,
  KOC Programmes, KOL Programmes, Add-ons with the term commitment and the
  Terms of Service, each table from the version's lines by `spec.role`, its
  words and settings (`{valid until}` filled), the foot PRIVATE &
  CONFIDENTIAL, the page count and `v.{version}.dp exp. {YYYYMMDD}` (`.dp`
  marks a card the portal drew, saved as `ADspace Rate Card v.{version}.dp.pdf`;
  one made by hand carries the version alone); the document's own type
  (11pt cells 5.76pt in, rows from 18.72pt, 18pt titles) on its 54pt
  margins; a line
  set inactive, or one no page holds (additional content, on request), is
  never printed. The Add-ons table opens on `addons_included`
  (`2026-10-13-rate-card-included-revisions.sql`, Wording).
- The rate card's section name is Ala Carté, as the team writes it, never
  respelled (the user, 2026-11-20: "keep Ala Carté"); its table writes
  "/ month" (2 content pieces / month), the card's own notation.
- What a quote reads of a line is `services.spec` (`service_spec_ok`), set in
  the line's sheet under Quotation details: a plan (letter, with or without ads,
  platforms, contents a month, its content options, the ad budget it
  covers, Best for), a platform's management fee, Meta advertising and an
  ads booster (the budget each covers), translation (an added language), a
  content format, a verification's own fee, a KOC package's creators, the
  KOL management fee's tiers, an add-on's group on the card.
- Quotations (`js/quotes.js`, `js/quotepdf.js`,
  `2026-10-14-quotations.sql`; the user, 2026-10-13: a quotation sent is
  honoured, and a client may hold several; the totals' rows on Build
  quote, the PDF and `/quote/` are `ADspaceMoney.quoteRows`, one copy,
  each page its own words, 2026-10-22, QT-4): one calculation,
  `quote_price(snapshot, selection)`, its totals worked by
  `quote_totals(lines, term, pct, sst)`, which `quote_adjust` and
  `issue_letter`'s quotation branch call too, never a copy of their own
  (2026-10-18), prices every quotation from the live
  version (`quote_card`), never the draft and never the page, on 3, 6,
  12, 18 or 24 months (`bad-term`; 1 for one-time items alone; the user,
  2026-10-14; the pages' one list `ADspaceMoney.QUOTE_TERMS`, held equal to
  `quote_price` by `tests/sql.js`; an extra content's line found by its
  `spec.kind`, never its slug), a plan included: a plan, its platforms (a dearer one inside the
  plan adds the difference, one past its count is an Additional platform
  at its fee), extra contents at the plan's whole saving to the nearest
  RM 10 (`extra_rates`), Translate every content (a content a language
  after the first), the advertising budget past the plan's cover (Meta
  advertising for the budget asked as one line, beside a plan Additional
  advertising budget coverage from its cover to the budget; past the largest,
  on request), one-time items
  apart; each monthly line takes the term percentage of its own months'
  band on its own subtotal, never more months than the term (`over-term`;
  `quote_line_pcts`, `totals.term_rows` a row a percentage beside the
  quotation's own `terms`; the user, 2026-11-15: "per line percentage"),
  priced on the Rate Card version Build quote's Rate Card version names
  (`p_sel.card`, `bad-card`; `rate_card_at`), else the one live on the
  quotation's Date, and the S$ rate in force on that Date, SST on the rest at
  the rate in force on the day it is priced (MYT), none for a client whose
  `sst_applies` is false (`quote_tax_snap`; a preview names its client in
  `p_sel.client`, never kept; `2026-10-15-quotation-tax-day.sql`). A
  client billed in S$ is quoted in S$ (`2026-10-15-quotation-in-sgd.sql`,
  `quote_fx` since `2026-10-22-bill-in-rm-or-sgd.sql`; the user,
  2026-10-15): `fx_sgd`, the ringgit to S$1 (Tax and terms,
  Singapore; four decimals, unset until the team sets it), turns every
  rate on the card to the cent (`quote_fx_snap`) and every RM figure in a
  line's words to whole dollars (`quote_fx_out`), the totals marked
  `currency` SGD with the `fx`; the budgets the page sends stay the card's;
  refused `no-fx` while unset (Build quote says so; a website lead is
  billed in RM, so quoted in RM, until Billing sets S$); Build quote, the row, the PDF and the
  website read S$, and a Letter of Offer takes the S$ lines as they stand.
  `quotations` (RLS: read at Clients: Services View under client scope;
  writes through functions alone) keeps each as sent: reference
  `ADP/QT{YYMM}-{Z}{NN}` (`quote_ref`), the version, the selection, lines
  and totals, valid for the days Build quote chose (`valid_days`: 14, 30, 45, 60 or 90, `bad-valid`), else `quote_valid_days` (30, Tax and terms), from its Date;
  never edited. The Services pane lists them above the lines
  (`#crmQuotes`; the Overview opens on them while any stand): the state
  worked out on read (Valid until, Expired, Ready to proceed, Revised, Letter of Offer requested, Not
  proceeding, Letter of Offer issued once a live letter holds its lines),
  the row two short lines (the plan and term, then who made it and when;
  2026-10-26), Preview PDF on the row with the step it waits on (Send
  link on WhatsApp, Resend on WhatsApp, Submit, Review), at a desk
  under the figure, the reference kept whole, equal halves under the meta
  on a phone; the ⋯ seven at most: Download, Link (a card hung from the ⋯,
  `#qtLinkPop`: the address, Preview and Copy link; 2026-11-08), Edit
  while it may be edited (on the row only where the ⋯ would pass seven),
  no Duplicate (the user, 2026-11-13: Build quote makes a new one),
  Send on WhatsApp, Send by email, Mark signed, Cancel / Restore
  (Cancelled), Remove with Undo
  (the user, 2026-10-22, QT-M1: "approve"). Show n removed quotations
  (`#qtGone`) opens a small list (`#qtGoneList`, `.qt-gonerow`, a `--sunk`
  box; the user, 2026-10-31: "it should make it small list"): a line each,
  the reference, what it was, Removed {day} by {name}, Restore and a ⋯ of
  Download and Delete, Delete at Clients: Quotations Full Access, the
  reference typed back, no restore (`quotation_delete(p_id, p_ref)`, the
  client in scope at Manage; `not-removed`, `bad-ref`, refused while a
  service line holds it, `lines` with the count, a letter quotes it,
  `letter` with its number, or a quotation revises it, `revised` with its
  reference; filed `client.quotation` {ref} deleted;
  `2026-10-31-quotation-delete-team-requests.sql`); a deleted reference is
  kept (`quotation_refs_kept`, RLS on, no policy, no grant), which
  `quote_ref` counts, so it is never issued again. The pane's one
  blue follows the deal (`paintDeal`, SL-M2): nothing quoted and no To
  quote line, Build quote; one quotation that can be offered, its Issue
  Letter of Offer (none blue where two can); To quote lines no live letter
  holds, Issue letter, drawn only once a To quote or Confirmed line
  exists; else none. An empty Quotations list reads No quotations. alone,
  Build quote the heading's (2026-11-03); an empty Service lines list reads
  the enquiry (else No service lines.), its Add service the heading's alone
  (the user, 2026-10-27). Build quote (`#qbBox`; Preview PDF under its lines, `#qbPreview`, draws the quotation as priced under DRAFT with the reference PREVIEW, nothing made and no number spent, and a quotation's ⋯ opens with Preview PDF, the kept file in a tab; the user, 2026-10-31; as the approved
  board: plan cards under Without ads / With ads, content, platforms with
  what each adds, extra contents as steppers with the plan's rate,
  languages, budget and term, one-time items as steppers two across (content,
  verifications, KOC packages, then every add-on with a rate under its
  card group: an outstation fee, a shoot, revisions, files; 2026-11-07; each
  one-time line carrying its service's description, a point a line, from the
  live version, `2026-11-07-one-time-lines-carry-their-description.sql`; a
  line's Qty typed sets its stepper, never an edit beside it, an older typed
  count moved into the stepper as the sheet opens; Create and Preview PDF
  rest from the first change until it is priced), the
  lines and totals from `quote_preview` as ticked, Monthly incl. SST kept in
  the foot (`#qbSum`); with no plan the
  platforms run four across and the budget sits beside the term) makes one (`quotation_create`, a key a press,
  made again whenever the selection changes; the same key twice, even at
  once, answers `again` with the first, and only for its own client, a
  website key its own visitor's email; 2026-10-19, audit 15; 2026-10-22,
  BE-4).
  Each line's Qty, Rate (RM) and Months (a monthly line's; the term
  until typed) are fields in the lines table (`p_sel.edits` by the line's
  `key`, kind|slug|label; `2026-10-15-quotation-rates.sql`, the user,
  2026-10-15: "fully customised for the rates qty and months"): priced
  again by `quote_adjust` inside `quote_preview` and `quotation_make`
  (`bad-edit`), the card's rate kept as `list_rate` and named under the
  line (Rate card RM …), the commitment counting each line's months,
  filed `n lines changed`; a website quotation is never adjusted; empty puts the card's
  figure back. A line's description is the Rate Card's until Edit under
  it rewrites it for that quotation (the edit's `detail`, one to twelve
  points of 300 at most, the card's kept as `list_detail`; Use Rate Card
  puts it back; 2026-11-13), which the PDF and /quote/ print; its name likewise (Rename under it, the edit's `name`, 1 to 120, the card's kept as `list_label`, Use Rate Card putting both back), the quotation a title of its own (`#qbHeading`, `p_sel.title`, 120, kept as `totals.title`, printed under Quotation on the PDF and over /quote/'s reference) and its lines in the team's order (Move up and Move down, `p_sel.order` by the lines' keys, `quote_order`, the figures never moved); a line changed from the Rate Card (name, description or rate) reads Changed (2026-11-16, the user: "too tightly controlled"). A line may be priced at RM 0, a complimentary line (the
  user, 2026-10-19): never refused. Beside a plan it is Include in plan,
  ticked unless the team unticks it (the edit's `incl: false`;
  `quote_adjust` stamps `in_plan`, a monthly line alone, never a one-time,
  `2026-11-07-quotation-fixes.sql`; the user, 2026-11-06, option A): no row
  of its own on the PDF or /quote/, listed under the plan's inclusions
  (`ADspaceMoney.planFold`, its count always stated, one singular:
  `1 × Additional reel, up to 60 seconds`), the totals
  unchanged; Build quote keeps its row, reading In plan.
  A plan card names its platforms, its contents (`6 contents: 2 graphics, 4
  reels`) and the ad budget it covers; choosing a plan ticks Meta where no
  platform is ticked; the budget opens on the plan's own (`Included: up to
  RM 4,000`, value 0, as the website sends it) and offers only larger steps
  from the card's Meta advertising and boosters, None where no plan covers
  one (the user, 2026-10-14). The pane reads Quotations (Build quote) over
  Service lines (Add service), each heading over its own list.
  No Letter of Offer is issued from a quotation (the user, 2026-10-31:
  the signed quotation is the contract; `quotation_offer` stays for a
  page served before and nothing calls it); the reviewer's approval makes
  its lines Confirmed (Quotation signing, below). Letters issued before
  are read, voided and deleted as before; a Letter of Offer is still
  issued from To quote service lines (Issue letter), and one not yet
  verified is reissued on its lines as changed from its ⋯ Replace
  (`issue_letter` `p_replaces`; the old one reads Replaced; 2026-10-31,
  the user: Car Connect SG's letter needed changes). The PDF (`js/quotepdf.js`,
  three pages; the user, 2026-10-31: one document, the quotation acting as
  the Letter of Offer): the Quotation Cover drawn by the letter engine
  itself (`ADspaceDocs.letterPages`, the team's Quotation Cover type in the
  console, the type as seeded on /quote/; signed off by who prepared it;
  never issued on its own, `docs/rules/documents.md`);
  the quotation on a continuation page with no second letterhead (a lead
  sentence, Description · Qty · Rate · Amount between hairlines, a line's
  inclusions under its name a point each as the service lists them (a
  bullet, the words hung under the first; 2026-11-04; /quote/'s lines and
  Build quote's alike, `ul.incl`), each
  amount in its currency with per month, one-time or its months under it,
  the totals at the right ending at the one bold figure, TERMS: validity,
  SST, budget billed separately, the whole term's commitment, binding once
  accepted and signed with the Service Terms, the rate card line); and
  Acceptance of quotation on a page of its own (the figures agreed, every
  bold total among them, the monthly and the one-time alike, Issued
  for and on behalf of ADSPACE PLT: Prepared by and Reviewed by, then the
  client's block to sign and stamp, Name, Designation, Date; unsigned and
  not a preview, the box a PDF signature field (draw, type or sign with a
  certificate in Acrobat) and each value a text field, through
  `ADspaceDocs.formFields`, the letter's own). Prepared by
  is the quotation's `made_by` (a website quotation's person in charge)
  with their position; Reviewed by the colleague who approved it, once
  reviewed; a signed copy draws the client's signature in its box and how
  it was signed under it (online: when, the email the code went to, the
  address and country, the fingerprint; paper: the day). Every page's foot: the reference, PRIVATE &
  CONFIDENTIAL, Page n of 3 (`ADspaceDocs.letterFoot`); named `ADspace
  Quotation {ref}.pdf`.
- Several brands on one quotation (`2026-11-24-quotation-brands.sql`; the
  user, 2026-11-24: "1x plan F and 1x plan B for another brand under same
  client entity"): `p_sel.brands` (1 to 10, each a `name` with its own plan,
  mix, platforms, extra, langs, translate, budget, once, edits, custom and
  order) is priced by `quote_compose`, each brand as a quotation of its own,
  its lines marked `brand` (its place), the whole totalled once by
  `quote_totals`, the names in `totals.brands`; the term, date, Rate Card,
  payment terms, validity, advertising budget, Bill to, terms and title stay
  the quotation's (one contract, one term); no `brands` is priced as before,
  and a website selection with them is refused (`bad-brands`). A line
  leaving a quotation of two brands or more (a service line on approval,
  a Letter of Offer's To quote line, each cycle's invoice line to Bukku) is
  named after its brand, `{brand} · {line}` (`quote_line_label`,
  `2026-11-24-quotation-brands-lines.sql`); one brand reads as before.
- A package (`2026-11-25-quotation-packages.sql`; the user, 2026-11-25):
  `p_sel.packages` (per brand where several, 1 to 5, console only, a
  website selection holding one `bad-package`), each a name, a basis
  (month or once), its months (the term where none, never past it,
  `over-term`), its price (the team's), its items (Rate Card lines of the
  quotation's card, never a plan nor a line on request, each once, a qty)
  with a content piece's `extra` (one more in the same month, the card's
  rate unless typed) and its `incl` (`{text, on}`, 20 at most), priced by
  `quote_packages` as ONE line, `kind` package, qty 1 at its price: detail
  the contents then the ticked lines, `excluded` the unticked, `extra`,
  `contents` (no rate: the client never reads a piece's rate inside a
  package) and `list_amount` (the contents at the card's rates). It leaves
  the quotation as any line (a service line, each cycle's invoice line,
  `{brand} · {package}` with brands); `ADspaceMoney.planFold(lines, cur,
  words)` prints what it leaves out under it as a sentence (Advertising
  management is not included.), once, on the PDF and the link; its rate
  for one more piece is an add-on rate, never under the line.
  `quote_files_cap` counts its graphics and reels.
- Add-on Rates (`2026-11-25-quotation-addon-rates.sql`; the user,
  2026-11-25): `p_sel.addons` (console only, quotation-wide, 200 keys at
  most, else `bad-addons`), a Rate Card add-on's slug or `extra:{slug}` for
  a package's rate for one more piece, kept by `quote_with_addons` as
  `totals.addons` (`{key, kind, group, name, rate, unit}`; the package's
  extras first in its order, then the card's add-ons in the card's order,
  from the quotation's own card and currency); never added to a line or a
  total. Build quote's Extras step ticks them (`#qbAddons`, none ticked on a
  new quotation, a reopened quotation keeping what it saved; the user,
  2026-11-25); the PDF prints them as
  a block anchored above the foot of the fees page (on the next page where
  it does not fit, running on under the same head), and the link reads
  them read only under its notes; none ticked, no block. A rate whose unit
  ends `, from` reads `from RM 450.00 per trip` (`ADspaceMoney.addonRate`).
  Wherever they print, TERMS' Exclusions read Add-ons are not included in
  the fees above. Each is confirmed in writing before it begins and
  invoiced in the month following its confirmation.: the month's invoice
  is issued on the 1st, so an add-on confirmed during a month is billed on
  the next month's invoice, whenever it is delivered.
- The quotation PDF's fees page (2026-11-25): PROPOSED FEES with the
  currency at its right; only a section the client pays is numbered (1
  Monthly Service Fee, 2 One-time Items, 3 Advertising Budget), each led by
  its glyph in a 22pt shaded disc with Billed monthly or Billed once at its
  right edge; no summary card; TERMS on the acceptance page above the
  Acceptance of Quotation, whose figures are plain body text.
- The term discount is the team's choice per quotation (`p_sel.term_disc`;
  2026-11-25): false takes every negative term percentage to 0
  (`quote_term_off`, kept as `totals.term_off`), a short term's surcharge
  kept; absent or true prices as before. Build quote's Term step draws
  Apply the term discount (`#qbTermDisc`) only where the term has one,
  ticked unless a quotation reopened kept it off.
- Build quote in four steps (the user, 2026-11-25, the approved boards
  "Build quote, step by step" and "Build quote on a phone"; `#qbTrack`,
  `.qb-pane` a step, `stepGo`): 1 Type (the brands in this quotation and
  the board's brand name, Choose what to quote as three tiles, Plan,
  Package or Items (`#qbTypes`, `kindPick`, a brand's own: choosing one
  lets go of the other's choices), Bill to where the client has two
  billing entities or more), 2 Build (Plan: the plan cards, content,
  budget, platforms, extra content and languages; Package: its builder
  (`#qbPkgBox`: name, basis, Rate Card lines with quantities, Rate Card
  value, Package price, Discount, Inclusions a tick a line);
  Items: the one-time items), 3 Extras (Rate per additional content piece,
  a package's, prefilled from the card; Add one-time item, the
  files held to their cap as before; Add advertising budget; Add to
  quotation), 4 Term and review (Term, Date, Payment terms, Valid for,
  Apply the term discount, More details: Title, Rate Card version,
  bilingual content, Custom items with Renew service lines and Add custom item, Terms; then the lines
  as the client reads them, Move up and Move down, Preview PDF). Continue
  checks its own step alone (`stepWrong`: Choose what to quote.; Choose a
  plan.; Enter the package name.; Add a Rate Card service to the package.;
  Enter the package price.; Choose at least one item.), Back keeps what
  was entered, and a quotation opened again (Edit, Adjust and send) opens
  at Term and review. A package's line is changed in its builder alone,
  never in the lines (`ownLine`, as a custom line). At a desk a summary
  stands beside the steps (`#qbSide`: the board's lines and the monthly
  figure incl. SST); on a phone Step n of 4 heads the track and the foot
  holds the figure over Back and Continue as equal halves. The suites
  open a step through `ADspaceQuotes.stepTo(n, kind)`.
- A quote part-built is kept as a draft (`2026-11-25-quotation-drafts.sql`;
  the user, 2026-11-25): a new quotation's Build quote closed before
  Create (the close mark, Cancel, Escape, the scrim) keeps what was entered
  (`draftOut`: the type's choices, brands, lines, extras, term, the step it
  was on; the date only where typed back from today) through
  `quotation_draft_save`, one a client a colleague (`quotation_drafts`, RLS
  on, no policy, no grant; the three functions ask a colleague at Work on
  `clients.quotes` and the client in scope, `denied`, `client-scope`,
  `bad-request`, `too-long` past 200 KB), said Draft saved. under the
  pane; a close that changed nothing since the sheet opened saves nothing,
  and Edit or Adjust and send keep none. Build quote opened again on the
  same client draws `#qbDraft` (`.draftline`) at the top of step 1: Draft
  saved {date}, {time}, Discard (asks Discard draft?, This cannot be
  undone., the draft's selection emptied) and Continue draft (opens at its
  step, priced on the version live on its date unless one was chosen;
  priced on another version than it was saved on, `#qbMsg` reads
  Repriced on Rate Card v.{new}. The draft was priced on v.{old}.). A draft
  keeps no number and no PDF. A console quotation made clears its maker's
  draft on the client (`quotation_drafts_clear`, on insert), so Create
  clears it. The phone's own sheet draft (`js/sheet.js`) leaves `#qbBox`
  alone (`tests/quotedraft.js`).
  At a desk the Summary is the cart (the user, 2026-11-25; `sidePaint`,
  `#qbSide`, sticking under the sheet's head and scrolling on its own where
  taller than the body): every priced line under Monthly, One-time and
  Advertising budget (Per month, billed separately, Up to RM {budget}),
  each with its amount, then the totals in the quotation's own order
  (each group's subtotal before its SST, the term adjustment where it applies,
  Monthly incl. SST, One-time incl. SST), one mute line counting the
  Add-on Rates ticked (3 add-on rates listed; No items. while none is
  priced), and a ⋯ on each of the board's
  lines (`.team-act`; Edit for a custom line, opening More details on
  Term and review; Change tax code, asked in a sheet from `taxOpts`, the lines'
  one list; Move up; Move down; Remove for a custom line or a one-time
  item, red and last); it repaints as the steps change. View quote is not
  drawn while the Summary shows (`sideOn`), and a resize that brings the
  Summary back closes the lines turned open. On a phone, where the
  Summary gives way, the foot reads the monthly total incl. SST (with `· n
  brands`), View quote on steps 1 to 3 once a line is priced, its count
  of priced lines a `.tab-n` (the sheet turned to the priced lines, every
  brand's under its name, the brand on the board changed where read, the
  others read; its Back returns); at every width, then Cancel on Type or
  Back, and Continue, or Create quotation (Save when editing) on Term and
  review. Add to quotation under Extras puts the
  board's brand in Brands in this quotation (`#qbBrandList`: a row a
  brand, its plan, platforms and term, its monthly figure from
  `quote_preview`'s `brands`, Edit and Remove with Undo where it happened;
  the board's own row marked Editing) and clears the board for the next,
  the first press naming the brand after the client; Edit brings a brand
  back with Save brand and Cancel; a brand choosing nothing is not priced;
  one brand never pressed through Add to quotation creates as before. With
  two brands or more, Create asks One for all brands (the answer it opens
  on) or One per brand, which makes a quotation each from the same list,
  its own reference, PDF, link, signature and invoicing, a key each
  (`{idem}-{n}`); a revision stays one. The PDF names the Brands (one made
  per brand its Brand) in its facts and each brand over its lines, the
  totals the whole quotation's; /quote/ likewise, offering no Change.
  Brand name carries no `aria-required` (the one save check would hold
  Create on the empty name of a new board); a brand's name is required
  only once it chooses something (`bad-brands`).
- Quotation signing (`2026-10-31-quotation-signing.sql`; the user,
  2026-10-31: "Jane picks the reviewer, approve"): the client accepts on
  the quotation's link (a team's quotation takes one from
  `quotation_link`): company details and billing contact (prefilled from
  the record), the figures agreed, name, designation, a signature drawn
  or typed and the authority tick, then a six-digit code emailed by
  `quote-request` `sign` (the sign-in email's words and shaded code box,
  never the code in its subject; `quote_sign_code`, the service role's alone,
  kept hashed, 15 minutes, five tries, five an hour a quotation and ten an
  hour from one address, its `request_ip()` relayed by quote-request and
  let go an hour on (`caller_ip`; audit 2026-11-15); Turnstile) and
  entered in six boxes (`quote_sign_finish`, anon), which keeps the
  signature with its record (time, email, `request_ip()`,
  `request_country()`, device, fingerprint) and tells who prepared it and
  the person in charge (`quote.signed`). The link then reads Accepted
  (`accepted`), Welcome once reviewed and Active. The colleague who
  prepared it checks the entries (each company field correctable, kept
  from and to) and submits to a reviewer they pick
  (`quotation_reviewers`: Clients: Quotations Full Access or an admin,
  never themselves; `quotation_submit`); the reviewer, or an admin in
  their place after asking, approves (`quotation_review`: Billing filled
  where empty, needing Billing Work, `billing-access`, left alone where
  Bukku holds it; the quotation's lines Confirmed, made where none) or
  sends back with a note. Signed on paper is kept by hand
  (`quotation_paper`: the day and a link to the scan); Request signature
  again (`quotation_resign`) keeps the earlier one in `sign_history`.
  A signed quotation is the contract (`2026-11-04-quotation-audit-fixes.sql`):
  never revised (`quotation_replace` `signed`, no Adjust and send),
  cancelled or removed (`quotation_set` `signed`, the row held; Request
  again is its way back); a cancelled or revised one is neither submitted
  nor approved (`not-proceeding`, `revised`); a reviewer is offered and
  taken only where their own client scope reaches the client
  (`quote_sign_member_sees`); the code and the finish read the link again
  once the row is held; the record keeps `in_contacts`, the check reading
  Not in Contacts where the code went elsewhere; the record prefills its own
  link alone (a team's quotation, or the website quotation that made the
  lead), nothing once closed or expired.
  `quote_sign_codes` has RLS on, no policy, no grant. A team's quotation
  is sent to sign by the approved `quote_ready` WhatsApp (Send link on
  WhatsApp in its ⋯, while unsigned and valid; `quotation_resend`, its
  link made at the first send, to the primary contact's WhatsApp else
  phone, refused `signed`; 2026-10-31, after Meta refused a template
  asking for a signature as Marketing twice).
- The Quotation portal (`/quote/`, `js/quote.js`; read as the quotation website until 2026-11-25,
  `2026-10-14-quotation-website.sql`; the user's approved canvas, Website
  1 to 6): What do you need?, Platforms and plan (where social media is
  asked; each plan names its content, `4 content pieces per month: 2
  graphics and 2 reels of up to 60 seconds`, its budget on a line of its own, and
  once a plan is chosen its Additional content pieces per month are asked
  under the plans, after Content pieces per month where the plan holds two content
  options (1 graphic and 3 reels, or 4 reels; sent as `mix`, a string; the
  user, 2026-10-27); the user, 2026-10-14), Customise (languages: each
  content piece is in one language, the month's content pieces divided
  across those chosen at no charge; with two languages or more, Make every
  content piece bilingual, a tick with no price, cleared when one language
  is left, sent as Build quote's `translate` and priced there as
  Translation (the user, 2026-11-25, reversing 2026-11-24); budget;
  Choose your commitment of 6, 12 or 24 months alone, a segment, 3 and 18
  Build quote's (`quote_web_terms`); with a plan, Content production lists
  only the formats its additional contents do not; Additional files with
  the grey Optional tag (an optional add-on, the user, 2026-11-25), the
  card's File Release add-ons (Working files, Raw footage) as steppers
  wherever content is made, a count of content pieces, Working files at
  most the graphics the selection makes and Raw footage at most its reels
  (`quote_files_cap`: the plan's content option, its additional content
  pieces and the one-time content, each piece by its kind on the card,
  `quote_piece_class`; a file the selection makes none for is not offered,
  + rests at the cap and a count above it comes down; held server-side by
  `quote_website_sel` and `quote_change_sel`, what a sent quotation held
  staying allowed; Build quote warns, `quote_preview` `files_over`, never
  refuses; `2026-11-25-quote-files-capped.sql`), under one note in
  the user's words (`filesNote`: may be added now or requested later;
  charged per content piece; no figure), the change editor's alike; the
  delivery promise (`delivered`, high definition, formatted for the
  platform it is posted on) the plan's last included tick, and the one
  tick of one-time content without a plan; every other add-on and an outstation fee Build
  quote's; verification only for the platforms chosen),
  what is chosen and typed kept in the tab only while the steps are gone
  through (a refresh keeps the place) and cleared whenever the opening page
  shows (the user, 2026-10-14: "dont cache my record"), Your details (salutation, optional, from the contact sheet's list, kept on the lead's contact (`2026-10-14-quote-website-salutation.sql`); name, work email, a Malaysia or
  Singapore WhatsApp number, brand, industry, Planned commencement, the
  one question for the start (ONE START QUESTION, 2026-11-21; the user:
  "Yes"; required on the page: Within 3 months, 3 to 6 months, More than 6
  months or On a specific date, which alone opens Preferred start date,
  required then; the period kept as the lead's Urgency to commence, worked
  out from a date chosen (`startPeriod`: up to the day before the same day
  three months on, Within 3 months; six, 3 to 6 months; else More than 6
  months), moved on a lead asking again and named in the team's notice; no
  price reads it; `2026-10-29-quotation-website-commence.sql`), the
  Preferred start date (a day from today in Malaysia to 2099,
  `commence_on` in the contact, `bad-start-date`; kept on the quotation it was asked on,
  `quotations.commence_on`, never the client (`clients.commence_on` is
  read and written by nothing, left for a later drop), named in the team's
  notice, read on the quotation's row as Preferred start {date} under where
  it came from (a revision reads the day of the quotation it revises), and
  Approve's Start date and Invoices' Set start date open on it, saying so;
  `2026-11-21-preferred-start-date.sql`,
  `2026-11-21-start-date-on-the-quotation.sql`), consent; a free email is
  advised against, never refused), then the quotation priced by
  `quote_price` through `quote-request` (Turnstile, every request refused
  while the secret `TURNSTILE_SECRET` is unset; Verify JWT off), which calls
  `quote_website_create` (the server's alone): a lead one of whose contacts
  holds both the email and the number is used again while Lead, Contacted
  or Proposal sent; else a client at any other stage (Active, Paused, Past)
  one of whose contacts holds both takes the quotation on its own record
  (Services, needing the team; no lead made, the record left as kept, no
  Planned commencement written), its person in charge told (`owner_id`,
  an active colleague; kind `quote.website`), else the leads managers at
  Full Access or an admin; two clients holding the same email and number
  pick neither, and a company or brand name alone never matches
  (`2026-11-25-website-quotation-finds-its-client.sql`); else a lead made
  (Source Website, nobody's), the
  quotation kept with `source` website, its key (`?q=`) and the brand typed
  (`contact.brand`, what the visitor reads back), five a contact a day
  counted under a lock on each, only the selection keys the price reads
  kept, the number read as `wa_number` reads it (`quote_website_number`;
  `2026-10-15-quote-website-guards.sql`, audit S1, S2, I2). No rate is
  shown before the quotation (the user, 2026-11-25: "Prices after we
  send"): `quote_catalogue` (anon) holds none, `tests/sql.js` reading its
  payload for any rate key or Rate Card fee. What a website selection may
  hold is `quote_website_sel`, read by the create (6, 12 or 24 months, else
  `bad-term`; `translate` true alone and only with two languages or more,
  `quote_catalogue` `translation` saying whether the card prices one,
  `2026-11-25-quote-website-bilingual.sql`; of the add-ons the File Release group alone,
  else `bad-once`; `2026-11-24-quote-website-choices.sql`). Prices are
  shown on the quotation the team sent alone, where the prospect may
  change the plan, content option, platforms, additional content, files
  and commitment and see the price follow on the quotation's own Rate
  Card, every line the team added kept (`quote_website_preview` by the
  link's key, anon, writing nothing); a changed selection is never signed:
  Request these changes keeps it on the quotation (`change_request`,
  `change_requested_at`, a minute apart, ten requests or withdrawals a link
  an hour then `busy` (MINOR ABUSE PATHS HELD), `unchanged` refused, the reply due
  by `quote_reply_by`, the team told `quote.changes`), Accept and sign
  waits (`quote_sign_open` refuses `changes`) and Withdraw request clears
  it; the console row reads Changes requested, Reply by its day, and Adjust
  and send opens Build quote on the prospect's changes, its revision the
  link's next quotation (`2026-11-25-quotation-changes-requested.sql`). A
  quotation holds at least one priced line: items quoted on request alone
  (a KOL campaign, a custom creator list) are refused on the page before
  the details are asked and by `quotation_make` (`nothing-priced`, no lead
  made; `2026-10-29-quotation-needs-a-priced-line.sql`). The price waits
  for the team (the user, 2026-10-29, Option 1;
  `2026-10-29-website-quotation-reviewed.sql`): a website quotation is
  kept with `reply_due` (`quote_reply_days` working days) and the leads
  team told Quotation to review; until a colleague sends it
  (`quotations.released_at`) the link reads Request received and the day
  it will be sent on WhatsApp, as the page's cover (2026-11-20), and `quote_website_read`
  answers no lines, totals, version or validity while it is unsent,
  whatever its stage (`quote_proceed` refuses `not-sent`). On the lead's Services it reads
  Awaiting review · Send by {day} with two ways to show it, each asked and
  valid from that day (`quotation_release`, no page's to call; Clients:
  Quotations at Work, the client in scope; the user, 2026-10-31: "publish
  quotation / send quotation", never a tick): Send quotation
  (`quotation_send`), drawn only while the `quote_ready` template is on
  and never for a prospect marked Do not contact (`no-contact`), queues
  that WhatsApp, filed as sent on WhatsApp, and is the pane's one blue;
  Publish (`quotation_publish`, the Publish glyph, tonal beside it, the
  blue where Send is not drawn) shows the rates on the link alone, nothing
  queued, filed published on the quotation link;
  Edit beside them (in place, below), no Send on WhatsApp; the managers are told
  six hours before the reply is owed while it waits (`quote_proceed_remind`).
  Once sent, the rates show, with Download (the A4 PDF); the website asks no
  billing and never a Letter of Offer, which the team sends after a
  conversation, the billing through the Details form
  (`2026-10-26-quotation-website-follow-up.sql`; the user, 2026-10-26).
  Beside it (under it on a phone) Ready to proceed?, never a free
  proposal: when they would start (Within a month, In 1 to 3 months) and
  whether they decide (Yes, I will involve others), both asked, then
  Proceed with this quotation (`quote_proceed(p_key, p_start, p_decider)`,
  anon; `bad-answer`, `expired`, `not-proceeding`; `proceed_at`,
  `proceed_due` the moment plus `quote_reply_days` working days, 2, Tax
  and terms), Request received with the day the team will be in touch.
  Once a colleague takes the lead the page names them (Your
  representative: name, position, Chat on their WhatsApp only where their
  namecard shows the mobile, else the office's); until then every step
  offers the office's Chat on WhatsApp (2026-10-27, QTE-2). The link shows the latest
  revision (`quotations.replaces`, `quote_shown`: Revised on {d}. It
  replaces {ref}.). The link follows the prospect to the client portal
  (`2026-10-26-quotation-to-client-portal.sql`): `quote_website_read`
  answers one `stage` (quote, ready, billing with the client's open
  details form's key, billing_sent, letter while a Letter of Offer stands
  on the quotation's lines, never lines made with no letter, signed,
  welcome once verified and Active, expired, closed once Cancelled;
  billing only on the website quotation that made the lead, never one
  that matched an existing lead or client; unsent, one kept on a client
  already served names no representative or preparer and reads its market
  from the number typed (`quotematchsql`); `quote_proceed` judged on the revision
  shown; a name or brand holding a web address refused, `bad-name`,
  `bad-brand`, `quote_link_like`) and the panel beside the
  quotation follows it, the representative under each step; Welcome
  offers Sign in to your client portal (`/client/`) where the prospect's
  address holds portal access, never a sign-in itself; expired keeps
  Request received where they had said they were ready, with New
  quotation and Chat on WhatsApp. The team who work leads are told at each step (kinds
  `quote.website`, `quote.proceed` with the answers;
  `ops_notifications.client_id` opens the lead's Services); while nobody
  has taken the lead, the managers (Clients: Leads Full Access, or an
  admin) are told once six hours before the time ends
  (`quote_proceed_remind`, pg_cron every fifteen minutes). The prospect
  is sent one WhatsApp, `quote_ready` (greeting, brand, reference; its
  link button the key), when a colleague sends the quotation; nothing is
  sent by itself; Send quotation and a website quotation's Resend on WhatsApp
  stop at `quote_wa_day` Quotation ready messages a day (MYT, `quote_wa_allowed`,
  `wa-limit`; Publish and a team's quotation are not held; 2026-11-10). On the lead's Services a website quotation reads Ready to
  proceed · Contact by {day}, offers Adjust and send (Build quote on its
  selection, saved as its revision through `quotation_replace`, then the
  WhatsApp composer) and in its ⋯ Do not contact / Allow
  contact (`quotation_set`, a website quotation's alone; no reminder
  while marked); a revised one reads Revised · By {ref}. A KOL campaign
  and a custom KOC list are quoted on request.
- What changed before Submit (QUOTATION PREFLIGHT, `2026-11-25-quotation-preflight.sql`;
  the user, 2026-11-25: "like a concert ticket checkout"): `/quote/` asks
  `quote_preflight` (anon, 240 an address an hour, `limit`; never a price)
  on reaching Your details and again on its Submit, with the Rate Card
  version its catalogue read; each change is one line over the details
  (`#qsPfBox`, the amber dot, its act at the right): the Rate Card updated
  (Continue), a plan, content option, platform, additional content,
  bilingual content, commitment or one-time item no longer offered, or files
  counted past the pieces chosen (`cap`, `quote_files_fit`'s count) (Edit,
  to its step), the page switched off (no act). The catalogue is read
  again and what it no longer offers leaves the selection, but a line
  stays until its step is visited, and Submit is refused in place while
  one stands. `quote_web_changes` is the one list of what the card no
  longer offers (`quote_website_sel` asks it for `bad-term`, `bad-once`),
  `quote_web_check` adds the page and the version; the create runs it
  before anything is written (`changed` with the list) and holds the
  version it checked (a card published between undoes the request), the
  quotation's row and its Quotation requested line naming that Rate Card
  version. A sent quotation's Request these changes asks it with the key
  and the totals shown: `price` where they moved, a choice refused by
  `quote_change_sel`, said in the panel, the preview read again.
- A quotation's sections (2026-11-12, `2026-11-12-quotation-sections.sql`,
  `2026-11-12-quotations-advanced.sql`): one made from then on (`totals.layout`
  2) prints Monthly Service Fee, One-time Items and Advertising Budget, each
  closing on its own total, the term's total a sentence in TERMS, the term
  row a discount or a surcharge (`ADspaceMoney.termLine`, in Chinese on
  /quote/'s 中文, a row whose lines run different months naming none); an older one redraws
  as kept. Build quote asks Payment terms (NET 7 unless chosen, the choices bare: the team decides; 30 and longer
  subject to ADspace's approval, `payLine`) and Include advertising budget (a
  row a platform, Monthly or One-time; the client's money, kept in the totals,
  never a service line or revenue; `quote_extras`; in an S$ quotation the
  Singapore ad account's own S$ figure, typed, never a ringgit tier turned
  over: its row opens empty and Create asks Enter each platform's budget in
  S$., the user, 2026-11-24). Its Advanced switch adds
  custom lines (`quote_custom`, priced by `quote_totals`, a quotation of them
  alone through `quote_base`), each with a start printed as its period; Renew
  lines (a client's confirmed lines, each `renews` its line, confirmed for the
  new term on approval and never added twice); Bill to (a billing entity,
  held as printed, `quote_client_extras`, the cover's To); and the quotation's
  own terms, ten at most. A Rate Card one-time item may be quoted Monthly (a
  number in its Months bills it monthly, empty or 0 keeps it one-time, as a
  custom line's and an advertising row's Months read alike, no Frequency
  selection; the user, 2026-11-12; `quote_adjust` edit `basis`, `was_once`, its
  percentage its own months' band). Every
  Months runs 1 to 36 and no more than the term; a term's percentage is `quote_term_pct`'s alone; a
  renewal starts the day after its line's period ends and every period's
  last day is `ADspaceClock.periodEnd`. On /quote/ a sectioned quotation
  keeps the monthly and one-time totals apart, lists the advertising budget a
  row a platform with its total, says its payment terms and own terms under
  it, and the signing page agrees every bold total; a Bill to quotation's
  signing opens on that company. The
  client's SST reads as Bukku's code at its rate (`ADspaceMoney.sstCode`, an
  SV code first), never that code offered twice, on Build quote and a service
  line alike. Approve asks Start date (`quotation_lines_start`: the
  quotation's confirmed lines with no start take it), and New month marks
  the months no dated confirmed monthly line covers No service line, saying
  under the field what covers the month chosen; it refuses none (older
  clients hold no lines yet).
- A quotation is edited in place until the portal sends it out
  (`2026-11-06-quotation-edit-until-sent.sql`; the user, 2026-11-06:
  "Quotation is a serious one so it must be accurate", Download never
  locks it): `quotations.sent_out_at`, stamped by trigger when a website
  quotation is released, or a WhatsApp for it is queued, sent or not
  confirmed, or an email for it sent, never while only filed or once
  failed (`2026-11-07-quotation-sent-when-it-went.sql`); a team's
  quotation also (the one the opened key belongs to, never a revision
  still being made nor one not proceeding) when its own link is first opened by anyone but a
  signed-in colleague (`quote_opened`, the console's Preview never asking
  it), never when it is only given its link: Copy link is not sending
  (`2026-11-25-quotation-sent-when-opened.sql`); nor an opening from the
  address a colleague copied that link from in the last 30 days (every
  Copy link press asks `quotation_link`, which records it), filed as
  `{ref} · Opened by the team` (`2026-11-25-quotation-copier-opening.sql`;
  its retention, `docs/rules/security.md`). Until then a team's quotation's ⋯
  and an awaiting website quotation's row offer Edit, Build quote opened
  as Edit {ref} whose Save is `quotation_edit(p_id, p_sel)` (Clients:
  Quotations at Work, in scope; priced again from the live card into the
  same row, its reference and link kept, a team's re-dated; `sent`,
  `signed`, `revised`, `not-proceeding`, `removed`; filed `{ref} edited ·
  RM a → RM b`), as often as needed; once sent out, Edit opens with
  Create quotation and makes the next quotation (`quotation_replace`).
- A quotation is issued as it is created, and is sent once it reaches the
  client (the user, 2026-11-26: "issued means created, only when issued to
  client means someone viewed the link"; asked whether a WhatsApp, an email
  or a website release still marks it sent, the user kept all four):
  Issued is every quotation, listed on the Register and found by /verify/
  by its reference and by its Document ID (`verify_find`, a removed one
  Void); Sent is `sent_out_at` as above, unchanged. A removed quotation
  that was sent out or signed is never deleted: its ⋯ offers no Delete
  and `quotation_delete` refuses it `sent`
  (`2026-11-26-quotations-issued-when-created.sql`).
- A quotation sent out or signed, and a Letter of Offer issued, move the
  client from Lead or Contacted to Proposal sent (`client_proposal_sent`,
  triggers `quotations_sent_moves_lead` on every write and
  `client_documents_moves_lead`, `2026-11-06-proposal-sent-from-every-route.sql`;
  the user, 2026-11-06: a quotation sent left the lead at Contacted), on
  its stage clock, filed `client.stage` Proposal sent · {ref} sent out,
  signed or issued; a later stage is never moved back, and a fault never
  fails the write. A trigger that must see a column a BEFORE trigger
  stamps names no column (`update of` sees only what the statement sets).

- A website quotation's ⋯ Preview (`quotes.js`, any reader of it; the
  user, 2026-10-30) opens `/quote/?q={key}&preview=1`: the prospect's page
  as they see it under one bar (`#qsPreviewBar`, `.annbar.previewbar`:
  Preview: the page as the prospect sees it. Nothing can be sent from it.;
  its × hides it, a refused press bringing it back),
  Proceed, a new quotation, Change selection and the billing form refusing
  in place (Not available in preview.), page-side; reading the link writes
  nothing. Once the quotation is sent, Copy link beside it gives the
  prospect's own link (no `preview`) to send again by hand, and Resend on
  WhatsApp (drawn while the `quote_ready` template is on) queues the
  quotation-ready message again (`quotation_resend(p_id, p_again)`,
  `2026-10-30-quotation-resend.sql`: Clients: Quotations at Work, the client
  in scope; `not-sent`, `expired`, `revised`, `not-proceeding`,
  `no-contact`, `wa-off`, `no-number`; within `wa_repeat_hours` `recent`
  with when and by whom, asked again in warn; filed under the colleague)
  (`tests/quotesite.js`, `tests/sql.js`).
- Website quotations at 0 (Settings, Messages; SWITCHED-OFF ACTS, release
  B): a waiting website quotation's Send quotation carries
  `data-gate="whatsapp quotewa"` and is drawn disabled with its reason, and
  the client's Quotations lead with one `.msg.warn` line (`#qtWaOff`); Send
  by email stays.

## Components

Moved from DESIGN.md §4 on 2026-11-22.

| Need | Component |
|---|---|
| A prospect's own quotation (`/quote/`) | The opening page (the boards QuoteIntroPhone and QuoteIntroDesk, 2026-11-25): the title over its line, no service tiles (the services are chosen on the Need step alone), What to expect as the shared step cards (`ADspaceIcons.stepCards`, DESIGN.md §4: a glyph in a white disc, its number on an ink badge), the time after its clock, then Chat on WhatsApp and Start as equal halves. The Need step (What do you need?; the user, 2026-11-25: "the five boxes replace here"): the services as tiles (`.qs-svcs` > `button.qs-svc`, one list `needKeys`), each a toggle (`aria-pressed`) on `S.need`: the glyph in its disc, the name, its line under it; a shaded card, white and ringed in ink once chosen with the several-of mark filled at its top right corner (as `.qs-pick`); three over two at a desk (a six-track grid, the last two half the row each), two across on a phone, a last tile alone taking its row; a thing drawn as a choice is a control a suite presses (2026-11-25: tiles on the opening page read as choices and pressed as nothing). Request received (QuoteReceivedPhone and QuoteReceivedDesk; no longer a cover) is the shared received page (`ADspaceIcons.received`, DESIGN.md §4, 2026-11-25): the title, the day as the statement, the reference and brand; the track (Request sent with its time, Review by ADspace In progress, Quotation sent on WhatsApp by its day, Accept and sign on this page); Your request (`ADspaceIcons.card`, `.qs-asklist`, a glyph a part of the selection kept, never a price); the representative's `contactCard` with Chat with {name} on WhatsApp (blue), else Chat on WhatsApp under the cards. Every glyph is `js/icons.js`'s, at 1.7 on this page. The plans (the boards QuotePhone and QuoteDesk, 2026-11-25): Without ads / With ads over three `.qs-plan` cards (its mark on top, `plancontent` or `planads`, the name, a line a fact with its glyph: content pieces, platforms, an ad plan's advertising budget), the middle one Recommended (`.qs-rec`, ink, on the mark's row at the card's right edge, never a row of its own; 2026-11-25) at 1.4 to 1, first and the row's width on a phone; under them the chosen plan (`.qs-plansel`, shaded): its name, best_for, its content each month (a segment `#qsMix` where two, else the one as a pill) and its inclusions a tick each; platforms with their ink marks (`ADspaceIcons.mark`, Facebook and Instagram one choice); never a figure. `.qs`, white to the edge: an opening page first (`.qs-intro`: the title, one line of what the page gives, What to expect as numbered steps `.qs-steps`, one mute line of time, validity and commitment, then Chat on WhatsApp and Start as equal halves; no step count), written to the client or lead using it, never to a colleague; then one 560px column a step (`.qs-progress`: Step n of m over a 4px track in `--fill`; the title; choices as `--sunk` cards, `.qs-pick` and `.qs-chip`, ringed in ink once chosen, never a browser tick box: a 22px mark at the card's right edge (`.qs-mark`), where several may be chosen a rounded square (6px) filled in ink with its tick, where one of a set a ring holding an ink dot; the consent tick the same square; a step's categories each under a 16/600 heading (`.qs-sec`), items 8 apart, the next category set off by a `--line-soft` hairline and a 24px step; steppers `.qs-stepper`; Back and Continue as equal halves; every choice of one line (a chip, a card with no line under its name), field, select, segment, stepper and button one height, `--ctl-h` (34 at a desk, 36 under a finger), a stepper's − and + the small control (`.btn-sm`, never `--ctl-h` set to the small figure); every control's words the portal's control text and a field's its field text, never a page's own; the title 26px, the lead's 16 times φ, its lead 8px under it); the quotation on the record's proportion at a desk (`.qs-quote`: the lines as rows with hairlines, the totals right aligned on `--sunk`, Ready to proceed beside it in a `--sunk` card, `.qs-side`: its two questions as `fieldset.qs-ask` of `.qs-pick` cards on `--card`, the one blue Proceed with this quotation at the card's width), on a phone under it; a step done beside the quotation is the green tick (`.qs-asked`); a quotation the team has not sent is the cover (Request received, the day it will be sent as the statement, the note and the reference under it, Chat on WhatsApp, with the colleague's name where one took the lead); a colleague who took the lead is a person card under the line about them (`.qs-rep`: a `--card` card, the name 15/600 over the position, Chat on WhatsApp tonal inside it; never an initials disc, 2026-11-07) |
| A client's quotations and Build quote | `#crmQuotes` (`js/quotes.js`) above the Services pane's lines: `.svc-row.qt-row`s (the reference over what it is, the monthly figure over its label, the state as `.chip-state`, a ⋯), two columns on a narrow pane. `#qbBox`, a 1000px `.formsheet` in four steps (`.qb-track` over the panes, `.qb-pane` a step; the type tiles `.qb-type`, a `--sunk` card ringed in ink once chosen; a package row `.qb-pkgrow`; the summary `.qb-side`, beside the steps at a desk): the plans as cards (`.qb-plan`: a radio mark, the letter and fee over platforms and contents; `--sunk`, the chosen `--line-soft`) under a Without ads / With ads segment at the heading's right; content and platforms (what each adds, `.qb-rate`) side by side; extra contents as steppers, languages, budget and term in three columns (one on a phone); the lines as a table and the totals right aligned, Monthly incl. SST the one bold figure; on a phone a line is its name over qty × rate and its subtotal; a line's inclusions run under its name a point each (`ul.incl`: 12.5 mute, the bullet hung), the figures on the name's line, on the phone the row's width |
