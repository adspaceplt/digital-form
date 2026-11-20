<!-- triggers: js/documents.js js/letters.js js/register.js js/verify.js verify/ js/docmail.js -->
# Documents (`js/documents.js`, `js/letters.js`, `js/register.js`, `js/verify.js`, `?s=register`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- One pen (`ADspaceDocs.pen`) and one letterhead for every document. The PDF is
  never stored: a row holds the snapshot and the file is redrawn on Download.
- Every document issued in the portal has a Date, today until changed
  (`2026-11-12-documents-on-their-own-date.sql`; the user, 2026-11-12:
  backdated "as per client's request", "the reference number must match"):
  a quotation (Build quote's `#qbDate`, `p_sel.date`, a team's alone, never
  kept in the selection), a Letter of Offer (`#pickDate`, `p_deal.date`) and
  a client, HR or supplier letter (`#docDate`, `p_issued_at`), 14 Aug 2023
  to today (`doc_day_ok`, `bad-date`, `ADspaceWords.line.docDate`). Its
  reference takes the date's period (AQL, ADP/QT, ADHR and AD/SCA its
  month, ACL its day), and it is priced on it: the SST, terms and S$ rate in
  force, the quotation still standing (`quote_card(date)`,
  `quote_tax_snap(…, date)`, `ADspaceDocs.quoteOf(…, at)`), its validity
  from it (the Letter of Offer's validity line moving with the Date while
  untouched). A quotation edited onto another month takes that month's
  reference, the one it held kept in `quotation_refs_kept`.
- Every PDF's properties are `ADspaceDocs.meta(pdf, title, subject)`: the
  title the name it is saved under (a reference keeping its slashes), author
  ADSPACE PLT, creator and producer ADspace Digital Portal (2026-11-12).
- Every PDF the portal hands over goes through `ADspaceDocs.save(blob, name,
  tab, zh)` under its own file name (Safari names a `blob:` address
  Unknown.pdf, and names a file after the last part of its address). The
  page's worker (`js/file-sw.js`, imported by `admin/sw.js` and
  `client/sw.js`) holds the drawn file an hour at `{scope}file/{id}/{name}`
  (the hour kept on every read; signing out lets go of the page's own,
  `ADspaceDocs.forgetFiles`; audit F6, 2026-10-10),
  and a tab opened at the press opens there: every Preview, and on an
  iPhone or iPad every save (`ADspaceDocs.tabFor()`, which opens no tab at a
  desk), so Save to Files keeps the name and nothing is asked. A download
  link never points at the worker's address (Chrome sends a `download` past
  the worker): a desk downloads the `blob:` under its name. With no tab (a
  blocked window) an iPhone's save takes the share sheet with a named File,
  asking File ready · Save (`ADspaceConfirm`; the client portal loads it)
  only when Safari refuses a stale press (`tests/savename.js`).
- In the installed app on a touch screen (`ADspaceDocs.installed()`:
  display-mode standalone or `navigator.standalone`, on iOS or Android) no
  window is opened for a PDF: a window on the app's own address opens inside
  it with no Share, Done or Back (the user, 2026-10-22). `tabFor()` and
  `previewTab()` (every Preview's one opener, Drawing the PDF…) open no
  window there: a Preview is read in a sheet with Close and Download
  (`#pdfViewSheet`; `previewTab()` answers a stand-in tab, `viewer`, that
  `save` reads; the user, 2026-11-07: no download asked for a Preview), its
  pages drawn one under another at the sheet's width by pdf.js 3.11.174
  (fetched at the first viewing, pinned by hash, its worker read and
  hashed before it runs; `paintPages`): an iPhone's frame drew page 1
  alone at its own size, cut at the right; a frame only where pdf.js
  cannot be had; its Download hands the share sheet the named file alone
  where files can be shared (a link to it opened a browser window over
  the app, offering the dead `blob:` address beside the file), else it
  downloads; a
  save goes to the share sheet as a named File (a stale press asks File
  ready · Share), and with no share sheet for files it is shown in the same
  sheet; a window on another origin
  (the Handbook's signed link, an invoice) is left as it is (`tests/pwapdf.js`).
- pdf-lib and fontkit are fetched on the first drawing (`ADspaceDocs.lib()`,
  waited on by every render: letters, reports, performance records); no page
  loads them in its head (1.1 MB, about 600 ms of a phone's load). A
  refusal names what failed: a file that arrives and fails its hash has
  changed at its source (Please contact ADspace: client pages draw PDFs
  too), anything else is the connection
  (fetched once more and hashed; `tests/pdflibhash.js`).
- Letter of Offer (kind `offer`; older rows `intent`, `cover`):
  - Retired (2026-11-12, the user: the quotation is the one contract): no new
    letter is issued; the client record draws no Issue Letter of Offer, Issue
    letter or Replace; a letter issued before keeps Download, Void, Delete,
    Verify, its sends and /verify/. `issue_letter` stands for the suites
    (`tests/issueletter.js` issues as the retired sheet did).
  - Billing first (2026-10-26; the user: "billing should be before LoO"):
    trigger `client_documents_billing` refuses a letter while the registered
    name, BRN or billing address is empty or no billing contact stands
    (`needs-billing`, as Active holds); the letter sheet opens Billing on
    its first missing field instead, offering the details form, and Billing's
    Save carries on into the letter sheet.
  - The ticked lines are locked before they are checked against live
    letters; a Confirmed line is tickable for a renewal; Replace is refused
    on a letter already replaced (`superseded`) or void (`voided`), and a
    deleted replacement revives the letter it replaced only where no other
    live letter holds its lines (`2026-11-07-letter-of-offer-fixes.sql`).
  - Serial `AQL/{client_code}/{YYMM}{NN}` from the lowest free slot. The
    counter's row lock serialises; the scan is capped (`no-serial`); two
    digits is a floor, not a width.
  - A typed reference (`p_serial`, the `#pickRef` field, placeholder "Numbered
    automatically") spends no number and is refused where taken
    (`serial-taken`) or badly shaped (`serial-shape`).
  - A client with no Client ID is asked for one in the letter sheet
    (`#pickCode`, `#pickRefNote`), the next AC number a press away
    (`#pickCodeNext`, Use AC…); the letter is refused until it is set,
    which Issue writes to the client first (filed from and to) and then
    numbers the letter from (the user, 2026-10-27, CLI-15).
  - The file name swaps `/` for `-`.
  - Preview (`#pickPreview`, a `.btn-sm` under Terms, never in the foot;
    the user, 2026-10-31) draws the letter Issue would keep: the database
    makes it and rolls it back (`issue_letter_preview`, issue_letter inside a
    subtransaction, its refusals passed on, `2026-10-31-letter-preview.sql`),
    drawn under DRAFT (INTERNAL USE ONLY) with the reference PREVIEW; no
    letter, number or Activity record row is kept.
- Letter content:
  - Only To quote lines.
  - Terms of its own (`#pickTerms`, one point a line, ten at most, 400
    characters each; `bad-terms`): sent in `p_deal.terms`, kept in the
    snapshot as `bill_to.terms` and printed under TERMS after the term
    (`2026-10-23-letter-terms.sql`). The box opens on the validity, today
    plus `quote_valid_days` (Tax and terms; `ADspaceDocs.validLine`),
    editable, never a figure in the page; such a letter carries
    `bill_to.terms_own` and prints no validity of its own, one issued
    before redraws its 30 days (the user, 2026-10-23,
    `2026-10-23-letter-validity-in-terms.sql`).
  - Priced by the month when every line of more than a month shares a term
    (the amount reading per month; the summary ending Monthly incl. SST in
    bold, as a quotation's does); a one-month line beside them is a one-off
    item (reading one-off) billed with the first month: one summary of
    Monthly subtotal, One-off subtotal, one SST line, First month due in
    bold, then Monthly incl. SST (the user, 2026-10-15: "just provide first
    month due total"; `2026-10-15-letter-one-off-items.sql` prices it).
    TERMS states the term once, with the whole term's total incl. SST; the
    acceptance lists Monthly incl. SST, Minimum term, First month due (with
    a one-off item) and Total for the term incl. SST, under no Item / Value
    head and never "including SST" after a figure. Lines on two terms of
    more than a month: Total incl. SST; a quoted letter so keeps its
    quotation's term (2026-10-18): the row `12-month commitment (5%)`,
    First month incl. SST under the total as the quotation gives it, TERMS's
    minimum term with the total over the months stated for each line, and
    the acceptance's First month incl. SST, Minimum term and Total for the
    term. Wherever a monthly line runs months other than the term, the
    month's figures are the first month's, named First month (excl. SST,
    incl. SST; 首月 on `/quote/`), and the first month holds the one-off
    items (the one-off subtotal before SST, one First month incl. SST, no
    One-off incl. SST of its own), on the letter, the quotation's PDF,
    `/quote/` and Build quote alike; Monthly where every line runs the term
    (the user, 2026-10-18). Where SST does not apply (an exempt client,
    0%), all four read SST not applicable on its row, name no SST on a
    total (Monthly, First month, One-off total) and leave out the excl. SST
    row; the quotation's remarks say once what the amount includes (the
    one-off items, SST at 8%), naming no SST at 0% (`ADspaceMoney.sstApplies`,
    `SST_NONE`; review item 17).
  - `priceOf()` computes the snapshot and the drawing. A letter whose every
    line came from one quotation is priced as `quote_price` priced it: the
    term percentage once on the subtotal, SST at the quotation's rate
    (`quote_sst` on each snapshot line; 2026-10-17), exactly as
    `quote_adjust` totals it: a line the quotation bills by the month is
    monthly whatever months Build quote gave it, and where they differ the
    whole span takes the percentage and SST once, the one-off apart
    (`quote_term` on each snapshot line; one without it redraws as
    issued), and prints each line
    at its rate before the term with the term as one summary row
    (`6-month commitment (5%)`), so its rows add up to the subtotal.
    `issue_letter` works
    the same price from the stored lines (the term's rate rounded to the
    cent, by the month where every line of more than a month shares a
    term with a one-month line its own one-off subtotal, SST at today's rate
    unless exempt) and keeps the page's figures only within a sen, else
    refuses `stale` with its own (audit S4, 2026-10-10). A colleague at
    Clients: Letters who cannot list quotations reads the quotation's rate
    and term through `letter_quote_terms` (2026-10-26); a line with no code
    is priced at the client's rate in the same group as a coded line at
    that rate, and every total is rounded by `cents()`, never `Math.round`.
  - `verify_letter` confirms only the lines as printed: a line removed since
    (`archived-line`) or one whose quantity, rate, term or adjustment moved
    since the letter (`changed-terms`) is refused, and the letter reissued.
  - `client_documents` keeps its read policy alone: every write is a letter
    or register function.
  - `legalName` is resolved once.
  - Every line wraps.
  - The contact is addressed with their salutation (`bill_to.contact_salutation`,
    `2026-10-14-letter-salutation.sql`): Attn: Ms Jane Doe and Dear Ms Jane
    Doe; the Billing pane and its contact select, and a client letter's Attn,
    read it the same way.
- Letter layout:
  - The closing is reserved on its own. The acceptance opens under the
    letter's grey hairline across the column with room either side (never
    ink: it read as a heavy black bar), and carries the
    sentence naming the reference and date, then the figures; the page
    count is the signed sheet's foot (Page n of n), never a sentence again.
  - The execution block is one table in the grey hairline (the user,
    2026-10-23: smaller, tabular): the signing and stamp cell at the left
    spanning Name, Designation and Date, a label cell beside each value.
  - The signing cell a PDF signature field, the other three transparent
    text fields in Helvetica (`ADspaceDocs.formFields`).
  - The reference and initials on every page but the signed one; the monogram
    only top right on page one.
- `issuer_name_ok`: the signatory is a real team name. It is never blank, never
  an email, never a role word.
- Void (verified letters only, with a reason) and Delete (the serial typed back
  and a reason) are Clients Manage, re-checked. Both revert only the lines that
  letter alone held (`letter_sole_services`).
  - A deletion row keeps no content.
  - A deletion frees its serial (`serial_taken()` ignores deletions); voided
    and superseded letters keep theirs.
- The Register lists `documents` and `client_documents` (`asOffer()`, family
  `offer`), banded Quotation Covers / Letters of Offer / Client Letters / HR
  Letters / Other.
  - Rows: Document · Brand · Recipient · Issued · ⋯ (a phone leaves Brand
    out). The HR card heads Team in place of Brand (`teamOf()`: `member_id`,
    else an Employee ID in the reference). The search reads a dash as a slash,
    as `/verify` does, so a file name finds its row.
  - An offer row answers to `clients.documents` and offers Open client record,
    never Void/Delete/Reissue.
- Serials per family:
  - a quotation cover takes the accounting portal's, typed;
  - a client letter `ACL/{client_code}/{YYMMDD}{NN}` (ADspace Cover
    Letter; the letter's date; the lowest number free for that client that
    day from 01, under an advisory lock); older `AD/[SA/]…` letters keep
    theirs;
  - an HR letter `ADHR/{staff_code}/{code}{YYMM}`.
  - `-2`, `-3` where an HR base is spent. `serial_taken()` spans both tables.
- HR is its own part:
  - `register_may(family, level)` is the read policy and the check in every
    write;
  - an HR row never arrives without `register.hr`;
  - the activity record logs the kind alone, under subject `HR`.
- An HR letter is shared with the colleague it names
  (`2026-10-06-hr-letters-shared.sql`, `documents.shared_at` / `shared_by`):
  Issue's Share with {first name} tick (`#docShare`) is on by default and
  off for a letter not yet theirs (a reissue keeps the earlier choice); the
  row's ⋯ Share with {first name} / Stop sharing (`document_share`, HR
  Letters at Work, `not-hr`, `no-member`). Shared, the colleague is told once
  (kind `hr.letter`, its kind and never its words; the bell and a push open
  Letters) and reads it in My records, Letters (`my_letters()`, behind
  `perf_mine_gate()`, their own alone, a replaced version left out, a voided
  one marked Void), its PDF drawn in their browser: no Documents access is
  needed. Filed under HR with the kind alone.
- Add existing document (`register_add` / `register_update`, ten arguments with
  `p_member` and `p_supplier`; opened on a colleague or a supplier from
  their record):
  - an HR entry names a team member and no client;
  - the document type is picked from the types already used for the family,
    with `__new` to type one, saved through `ADspaceForm.title`;
  - the date may be blank;
  - Edit applies to manual rows only.
- The client picker offers every record in the directory's bands, each A to Z
  by Client ID (`ADspaceForm.named`). A pick fills the recipient with the registered name,
  editable, and never replaces a typed one.
- Reissue (Work level, `document_reissue`):
  - voids the earlier version as Reissued and keeps it;
  - the new version keeps the serial and points back (`documents.replaces`);
  - the unique index covers standing documents only;
  - `/verify/` answers the standing version as Valid and never says reissued.
- `/verify/` (VERIFY DETAILS, `2026-11-20-verify-details.sql`; the user
  approved mockups A1 to A6) answers in two steps, in English and Chinese,
  with `?s=` prefilled, light and white to the edge, every cover's 440
  column. `verify_find` (no caller's) is the one lookup and the one state:
  an exact reference first, one typed with dashes for slashes (the file
  name's form) the same reference; the standing version first; never the
  recipient, a term or a figure.
  - The first answer (`verify_serial`, anon): found, the reference, the kind
    (HR is "HR Letter"), the state (Valid, Void, Replaced for a superseded
    Letter of Offer or a revised quotation, Expired for an unsigned
    quotation or an offer past its validity, Withdrawn, Declined), the month
    of issue (`issued_month`, drawn Nov 2026), `sealed`, `more` and `by_day`;
    no day and no Document ID. The page reads it as a shaded card
    (Reference, Issued by from `ADSPACE_ORG`, Document, Issued, Status) over
    "This answer confirms that ADSPACE PLT issued a document with this
    reference. It does not confirm the copy you hold.", then View more
    details and, for a sealed copy alone, Check a file, side by side (one
    over the other on a phone). A reissued document answers its standing
    version as Valid and never says reissued.
  - Every document /verify/ answers (`documents`, HR letters among them,
    `client_documents`, `quotations`, `hiring_docs`, `perf_reviews`) holds a
    Document ID (`doc_code`): eight characters of the link alphabet in upper
    case from `gen_random_bytes`, stamped on insert (`doc_code_stamp`,
    `doc_code_new`), unique in its table, printed XXXX-XXXX on every page
    through the one pen (`pen({ code })`: an ACL letter's verify line ends
    ` · Document ID XXXX-XXXX`, centred, clear of the page count; an AL
    quotation's stands at the bottom margin's left at `G.refAt`; a
    performance record's in its reference line); the page asks it by the id
    it holds (`ADspaceDocs.codeOf`, `doc_code_of`, anon too), never a
    preview's or a draft's. A copy sealed from 2026-11-20 prints it on its
    Record page; one sealed before printed its uuid, which still opens the
    details of a sealed quotation or offer.
  - The details (`verify_details(p_serial, p_code, p_day)`, anon) answer
    the day of issue, the Document ID, the state and the steps by Malaysian
    day (issued, sent, signed by the recipient, confirmed by ADspace, sealed
    copy kept, acknowledged, finalised, declined, withdrawn, void, replaced,
    expired; drawn with the status's dot, no weekday) only for the Document
    ID (any case, with or without its dash) or, for a document issued before
    `verify_code_from` (a Business setting, YYYYMMDD, seeded 20261120) or
    holding none, its day of issue (the fold "No Document ID on your
    copy?"). A wrong code, a wrong day and an unknown reference read the
    same (`no_match`): "No document matches these details. Please check both
    entries, or contact ADspace at {contact}.", `contact` the Legal and
    compliance mailbox (`mail_boxes` `legal`).
  - Check a file: the PDF hashed in the browser, never uploaded, its SHA-256
    asked of `verify_file` (anon): Matches the sealed copy or Does not match
    the sealed copy.
  - Counts: anyone the team does not hold is answered 30 references and
    file checks an hour a connection (`verify_count()`, `verify_tries`) and
    10 detail checks (`verify_detail_count()`, `verify_detail_tries`), each
    by `request_ip()`, RLS on, no policy, no grant, then `locked` with the
    minutes left before anything is read (Too many checks; Too many
    attempts); a session with no request is not counted; `privacy_retention`
    removes a row whose hour began over 30 days ago.
- The Chinese face (`ADSPACE_ORG.fontCjk`):
  - It is Noto Sans SC as TrueType in the repo (`css/NotoSansSC-Regular.ttf`,
    `css/NotoSansSC-NOTICE.txt`), embedded with only the characters used.
    The CDN's CFF face, embedded whole, made every Chinese PDF 8 MB and drew
    garbled in strict viewers. fontkit's subsetter needs every glyph's data
    at an even length, so the face is saved with its glyphs padded.
  - A CFF face is embedded whole, never subset (`isCff()`).
  - An unreachable face refuses the letter by name.
  - `fontMed` falls back to Slate Regular.
- Issue document (`#docSheet`):
  - The kind decides the fields.
  - The type seeds the title, salutation and body, with `{first name}` and
    `{role}` filled. A body somebody has edited is never overwritten.
  - The signatory is the signed-in person and their `designation`.
  - To be signed (`#docSigned`, sent as `p_signed`) is a tick prefilled
    from the type and fixed on a reissue: ticked, the letter leaves space to
    sign and needs a signatory; unticked, the name and designation follow
    ADSPACE PLT with no space and the foot reads No signature required.
  - The sheet runs in the letter's own order.
  - Preview (`#docPreview`, a `.btn-sm` under the letter's fields, never in
    the foot; DOC-6, 2026-10-22) draws the letter from the sheet
    on the same pen without issuing it: no row, no number spent, the
    reference reading PREVIEW (a reissue keeps its own), every page under
    DRAFT (INTERNAL USE ONLY) (the report's watermark, one copy:
    `ADspaceDocs.watermark`); a new tab, else a download.
  - A letter's foot is its template's (ACL_SIGN or ACL_NOSIGN, by To be
    signed; DESIGN.md, Print; 2026-11-20): the verify line centred
    (`ADSPACE_ORG.verifyUrl`, go.adspace.me/verify, which redirects to
    /verify/) and the page count; the reference stands in the body (Our
    Ref) and, on a lettered document of two pages or more, on every page
    in the bottom margin's left (Slate Book 6.5pt, `#a1a1a1`, level with the
    Client initials, `pen()` `ref` or `letterFoot`'s serial; 2026-11-20,
    the anti-swap reference restored; `pdfreal`). The inks are the pen's
    alone (DESIGN.md, Print): the wordmark and body `#515151`, titles
    `#1a1a1a`, every mark of the head and the foot `#a1a1a1`.
  - The register's sheets (`#docSheet`, `#regAddSheet`, void, delete)
    close on an outside click only while untouched, as `js/sheet.js` holds.
  - `doc_types` is seeded once and is the team's to edit: Document types
    in Settings' Templates alone (2026-10-29), `register.types`
    (`2026-10-07-document-types.sql`). `#dtSheet` lists them by group, as
    My Work's Templates; `#dtEditSheet` edits one: Group (fixed once made),
    Name (unique), an HR letter's Reference code (required, its own among
    the HR letters offered; the sheet and the list spell the whole
    reference, `ADHR/{Employee ID}/{code}{YYMM}`, never "Code E"), To be signed, Offered
    on Issue (`doc_type_set_active`; never removed, an issued document names
    its type), the wording, and Fields. Saved by `doc_type_save`, filed
    `team.changed` under Document types from and to.
  - A type's fields are the words its wording holds in braces ({intern
    name}, {from}); {first name}, {role} and {client} fill themselves, and
    on an HR letter {name}, the colleague's full name; a client picked in
    the Register's sheet brings its main contact (else its first), and
    Issue refuses any word still in braces in the title, salutation or
    letter, naming it (2026-10-27, DOC-7).
    `doc_types.fields` says how each is asked: Text, Date or Paragraph (a
    name holding "date" is a date until set). Issue groups the kinds
    (Quotation, Client letters, HR letters) and asks for them under Details,
    filling each into the title, salutation and body as it is typed (a date
    as `16 September 2026`; words typed over are filled on Issue); Issue
    refuses a field still in braces ("Fill in From."), Preview draws it as
    it stands, and `body.fields` keeps what was typed. A reissue keeps its
    words and asks nothing.
  - The Register sorts newest first, with Oldest first and By reference in the
    bar.
- The reference on a row is a copy control (`.serial-copy`).
- A hand-added row's second line is its kind alone.
- The old list is imported by a SQL file handed to the user, never committed
  (real names).
