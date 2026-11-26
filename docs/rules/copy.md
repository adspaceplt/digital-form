<!-- triggers: css/ js/ admin/ client/ creators/ creator/ review/ script/ verify/ card/ quote/ details/ feedback/ supplier/ careers/ demo/ index.html 404.html docs/PAGE-TEMPLATE.html supabase/ docs/SIGN-IN-EMAILS.md -->
# Copy (DESIGN.md §6)

Moved whole from `DESIGN.md` §6, which keeps a one-line pointer here; read whole before writing or changing any word a person reads (a screen, an email, a PDF, a WhatsApp template, a refusal).

- Every word on a screen, and every reply to the user, is proper, formal
  corporate English (the user, 2026-10-09: "not conversational nor weird
  language"): complete, plain statements of fact, never shorthand, slang or
  a phrase coined for the screen ("The portal is covered for the team" read
  as nonsense; "Everyone but admins sees the upgrade screen" does not).
- What a client reads (client pages, the Quotation portal, every PDF) is
  formal Malaysian business English, as a corporate letter here writes it
  (the user, 2026-10-13: "natural corporate, professional, formal"): Per
  month, billed separately, incl. SST, Registered Company Name; never a
  clipped or coined phrase (a month, billed apart, see my price). Nothing is
  said twice and nothing non-essential is said; a whole term's total is
  stated in the PDF alone, never on a screen.
- No explanatory copy: no hints, blurbs, notices or role descriptions.
  - The heading and the controls are the explanation.
  - Where a line is unavoidable, one neutral corporate sentence; no "we", no
    "you should".
  - A note on a client page reads one sentence a line (`ADspaceWords.note`,
    every `.qs-note`, `.qs-notes` and `.rcv-note`), never two run on (the
    user, 2026-11-25).
  - Nothing says the same thing twice (a cover line never restates its title;
    a chip never repeats its column).
  - The one exception is the route's one-sentence purpose, which opens from
    its name; the first-visit guides (two or three short steps a section, met
    once, `js/guide.js`); and Health, which speaks as the company where a
    colleague is asked to agree, answer honestly and seek help (the user,
    2026-10-07).
- Buttons:
  - one to three words, sentence case, verb first;
  - no article, and no object the context gives (**Delete**, never
    `Delete client`);
  - a menu item is the action's name only.
  - a sheet that makes a record reads as the bar button that opened it: its
    title is the button's words, and its commit repeats an Add button's words
    (Add lead, Add link, Add service, Add member) or reads Create under a
    New one (2026-11-03).
- Formal names take title case: documents, agreements, forms, checklists and
  reports (Letter of Offer, Service Agreement, HR Letter, Onboarding Checklist,
  Social Media Accounts Report).
  - Articles and short prepositions stay lower; acronyms keep their capitals;
    Pre-Advertising Checklist.
  - An official or professional term keeps its capitals wherever it is
    written, on every page of the portal, a label, a refusal, a
    placeholder, an email and a PDF line included (the user, 2026-11-09:
    "Passport, Tax Identification Number (TIN) etc. not every wordings
    should only capital the very first word", "not just cover the billing
    section but entire portal"): the field names of Malaysian identity,
    bank, LHDN and SSM forms, one name a field (Full Name as per NRIC, Full
    Name as per Passport, Registered Company Name, NRIC, NRIC Number,
    MyKad, Passport, Passport Number, Business Registration No. and
    Business Registration Number (BRN), Old Registration No., Tax
    Identification Number (TIN), SST Registration No. and SST Registration
    Number); the formal names above; and a section's or product's own name
    (Creators List, Content Review, Rate Card, Google Meet, Meta Business
    Suite, Bukku; the user, 2026-11-10: Rate Card on every screen). The label's other words stay sentence case (Billing address,
    Finance email, Payment method), as does a common noun (quotation,
    invoice, letter) and a term not plainly an official one.
    `tests/words.js` fails a lower-case official term.
  - Everything else is sentence case.
- Back / Revert / Restore / Reinstate / Undo as in `CLAUDE.md`; never "Return".
- Remove and Delete are two promises (the user, 2026-10-31: "Remove means
  can be added back; Delete then gone forever"): Remove hides or takes
  away and can be brought back (Undo where it happened, Restore or Enable
  after); Delete is gone for good, asked first and named so. A control
  that cannot be brought back never reads Remove, and one that can never
  reads Delete.
- One word per act, everywhere (the user, 2026-10-09: "why do you use
  different terms"): Publish / Unpublish (never Share, Unshare or Publish to
  client), Download, Preview PDF beside it where a record draws one, Add
  for the next of a series (Add script). `tests/words.js` fails a retired
  word. A ⋯ item names what it opens or acts on wherever the bare word is
  unclear out of its row (the user, 2026-11-21: "can you not too short",
  "also check other parts menu wordings"): a bare noun takes its verb and
  object (Show versions, Show document record, Show quotation link, Show
  who acknowledged, Open signed copy, Set access code (Show access code
  to a reader at View), Edit Meta accounts,
  Add pictures from Meta), a download its file (Download PDF); a verb its
  row makes plain stays bare (Edit, Delete, Remove, Duplicate, Rename,
  Restore, Reset link, Void, Withdraw, Reopen).
- One vocabulary:
  - Creator steps: Confirmed, Pending visit, Pending draft, Submitted,
    Reviewing, Changes requested, Scheduled, Posted, Completed, Withdrawn.
  - Service lines: Enquired, To quote (never Quoted), Confirmed.
  - Client stages: Lead, Contacted, Proposal sent, Active, Paused, Past.
  - Requests: Requested, Reviewing, Approved, Declined, Applied, Withdrawn;
    kinds Upgrade, Downgrade, Cancel, Change of details.
  - On/off: Active / Inactive.
  - Performance: Draft, Shared, Query raised, Query answered, Acknowledged,
    Final; an issue (never breach), notes and a reference (never evidence),
    a query (never dispute) answered Agreed, Partly agreed or Not agreed;
    grades Needs support and Improvement plan; the recovery path.
  - My Work: Assigned to, Content task, Posts, For, Month, Format, Due date,
    Draft due, Post date, Checklists.
- The first of several is primary, never main (the user, 2026-10-29: "who
  says make main so weird"): Primary contact, Primary billing entity, Make
  primary; the stored keys (`is_primary`, `is_main`) never move. A word a
  corporate reader would not write in a letter is not on a screen.
- A step the reader waits on is said as what will happen (ADspace will
  review your request and send your quotation), an Undo answers Undone.
  (never Put back.), and a line names the thing as its reader knows it (the
  notice page, never the cover; Refresh the page, never Read again where no
  Read again button stands) (2026-10-29).
- Words are the ones people already use at work, never a legal, police or
  system word (the user, 2026-10-05: "why use evidence. Sounds like some
  criminals"). Only the words change; stored keys never move.
- A state is named for what is true when it is set. A field about a person
  records what we do ("Prefers English", Preferred language). A cover title
  names the outcome (Access denied). A section is named for what it tells you
  (Portal access, Person, Sign-in email).
- A control is named for what it does:
  - Enable backup selection.
  - Add creator.
  - Request extension, when it will only ask.
  - Creators List (never "roster").
  - Assigned to and Created by (never Task Owner, Owner or Manager);
    Reassign; Unassigned.
  - Add another; Create 3 tasks.
  - Import from spreadsheet.
  - Transfer client (a report to the client it belongs to), never Move to
    client.
  - White label (on a client's Brand: its reports carry the client's wide
    logo; on a report: the white-label client and the brand it covers);
    Wide logo; Brand on the report.
- Headings name their content: Task details, Posts, Schedule, Repeat,
  Assignment, Date and time, Meeting channel, Frequency, End of repeat, Call or visit
  details, Contact details, Task settings, Inclusions, Stage timeline, Team
  member.
- Messages:
  - a success is one or two words ("Saved.");
  - a validation names what is required;
  - an empty list is two words ("No entries."), and no line says "yet"
    (Not issued, Not set, No reviews.).
  - A missing value in a table cell is a mute em dash (the one place a dash is
    allowed).
- A client document proposes and states, never demands: no payable, must
  or shall pay in a heading or a label (Proposed Fees, never Fees
  payable; the user, 2026-11-25); a contract clause in TERMS keeps its
  legal shall.
- Content is uncountable: a client page, a quotation and its PDF count
  content pieces (`6 content pieces per month`), never contents; no
  contraction or exclamation mark, and no chat words (Hand in, Needs you,
  Let us know) where a client, creator, prospect or supplier reads (the
  user, 2026-10-27). In Chinese a creator is 创作者 on every page, never
  博主 or 达人.
- What is billed once is one-time, never one-off (One-time subtotal, One-time incl. SST; the user, 2026-11-25), in every word a person reads; the stored keys (`once`, `basis`) stay.
- Count creators, not slots. rednote is lower case; never Xiaohongshu or
  RedNote. Say Post, never Note.
- Placeholders: a value a person would type, from one generic set: John Doe
  (Jane Doe for a creator), email@adspace.me (a colleague's
  email@adspacestudios.com), @adspace.advertising, ADspace Advertising (a
  Facebook page), 012-345 6789, 07-123 4567, https://adspace.me, COMPANY
  NAME SDN BHD, AC001, AD001. A field with no natural example keeps a short
  hint (Optional, One point a line). Never a real client, creator or
  colleague, nor a code one could hold.
- A WhatsApp template's body is set out as a letter (the user, 2026-10-31):
  the greeting on its own line, a blank line, one point a paragraph, each
  detail (reference, brand, date) on a line of its own, and a blank line
  before the closing; never a sentence broken across lines.
- A WhatsApp template's footer reads `{What it is} - ADspace Digital`
  (Quotation - ADspace Digital, Approval Reminder - ADspace Digital; the
  user, 2026-10-31), and its wording states a fact about the client's own
  record, never asks them to buy or sign, or Meta files it as Marketing.
- ADspace alone, never "ADspace Studio" (a strict rule).
- Brand names exactly: ADspace, S P Setia, CraftStone, Home Leader, The Mill
  International, EV SUN, Foodince, Furiku Matcha, HKL Lim, HKL Lim Motorsport,
  Star Living, Niro Granite, Dale & Cecil, Dale, Gadang Holdings Berhad.
- Chinese is localised, not translated: 下午2:00, never pm; a figure and its unit with no space (42分钟); the full-width comma (2026-10-20, POR-3, VER-1).
- No dashes in copy where avoidable. Dates `12 Sept 2026`, months `Oct 2026`,
  money `RM 8,490.00`, agreement prose `16 September 2026`.
- A date the reader waits on (a deadline, an appointment, a page back by) carries its weekday: `20 Nov 2026 (Friday)`, `2026年11月20日（星期五）`, with its time `20 Nov 2026 (Friday), 12:30pm` (`ADspaceClock.date` `named`, `ADspaceClock.due`; `named: 'ahead'` once it has passed); a history date never does (the user, 2026-11-20).
- Client-page cover words live in `js/words.js`:
  - "Link not recognised / Please contact your ADspace account manager.";
  - "Access code / Enter the access code provided.";
  - "Unable to load / Please refresh…".

### How copy is drafted (the user, 2026-10-29: "write down how you draft your tone … so it wont need me to repeatedly check")
Every word a change puts in front of a person (a label, a button, a menu
item, a message, a refusal, an empty line, a cover, an email, a WhatsApp
template, a PDF line) is drafted and checked this way before it is
screenshotted, and the push names any line it could not settle.
1. **Who reads it.** A colleague in the console: plain, short, the team's
   working words. A client, prospect, creator or supplier (client pages,
   /quote/, /details/, /supplier/, emails, PDFs, WhatsApp): a formal
   Malaysian business letter, full sentences, Please where it asks
   something of them, no contraction, no exclamation, no chat word.
2. **Say it as a letter would.** Read the line aloud as if it were in a
   signed letter or on a bank's website. A word that would not be written
   there is not written here: Primary, never main; Undone., never Put back.;
   a control the short word a familiar app uses (Duplicate, Cancel, Repeat,
   Clear filters, Reassign), never a phrase where one word says it;
   Refresh the page, never Read again (unless a Read again button stands
   beside it).
3. **Never the system's word.** A stored key, a column, a function, an
   internal term (`is_main`, cover, covered, slot, row, flag, payload,
   scope, stale) never reaches a screen; say what the reader sees or does.
4. **The reader's tense.** What has happened: past (Sent., Saved.). What
   will happen: future (ADspace will review your request and send your
   quotation). An instruction: the imperative with its object (Enter your
   brand name., Choose a colleague.). Never the present tense for a step the
   reader waits on.
5. **A refusal says what to do next.** What failed, in the reader's words,
   then the one act that resolves it: "The primary billing entity cannot be
   removed. Make another entity primary first." Never a bare "Not allowed."
   where a next step exists, never the database's words, never blame.
6. **One word per thing, one thing per word.** Before a new noun or verb,
   grep `js/words.js`, this section's vocabulary and the screen it joins;
   use the word already in use. A new word for an existing thing is
   refused; a word that names two things is split.
7. **Nothing said twice, nothing that explains itself.** The heading and
   the control are the explanation; a line under them adds a fact or is
   deleted.
8. **Chinese is written, not translated** (§6 above): the same check in
   Chinese, a 中文 version for every client-facing English line, read by
   its own rules.
9. **The short word a familiar app uses** (the user, 2026-10-31: "dont
   need long text just simple understanding ones would do"). A button or
   menu item is the one or two words people already know from everyday
   apps, never a phrase where one word says it; the screen around it gives
   the object:

   | Say | Never |
   |---|---|
   | Duplicate | Make a copy |
   | Cancel (the state Cancelled) | Not proceeding |
   | Repeat | Repeat on a schedule |
   | Reassign | Change person in charge |
   | Submit | Submit for review |
   | Share | Share with management |
   | Clear filters | Clear the filters |
   | Add lead, Add service | Add the first lead, Add the first service |
   | Make primary | Make primary contact |
   | Enable access, Revoke access | Enable portal access, Revoke portal access |
   | Do not contact, Allow contact | Mark Do not contact, Clear Do not contact |
   | Use passkey | Unlock with a passkey |

   Extra words stay only where they change what the act is (Confirm
   without letter, Send on WhatsApp beside Resend on WhatsApp, Issue Letter
   of Offer). A question's title may still name its object (Remove from
   Content Review?).
10. **Standard lines.** A delete question ends This cannot be undone.
   (never There is no restore); a record changed meanwhile reads Not saved.
   This record was changed by someone else. The latest version is now
   shown.; a record gone reads This {thing} no longer exists.; a label
   says per (Input price per million tokens, one per line), never "a";
   an off figure says (0 turns this off). A note after a select's option is copy too, a plain
   fact of one or two words, as long as the status beside it (Not planned,
   No content, as Published), never a fragment that leaves the reader
   guessing who asked (Not asked for; the user, 2026-11-02). A label cut to fit a column, a
   tile or a button (Qty × rate, Per engagement) stays short (the user,
   2026-10-31: "sometimes are cut short due to the width compatibility").
11. **A label is a noun** (the user, 2026-11-05: "Why it goes now" should
   be Reason). A field, a heading, a column or an option names the thing
   (Reason, Changes, Note, Enquiry), never a clause or question
   about it (Why it is late, What needs changing, Note for them); a refusal
   names what to enter (Enter a reason.), never Say why. Approved section
   names stay (What worked, Areas to improve, Why it stood out).
   Where the reader must act (rate, choose, tick, upload, decide, confirm),
   the heading over it says the act, verb first (Rate your experience,
   Choose your platforms, Upload your invoice), never a noun that could read
   as something already done (the user, 2026-11-22: "Your experience" over
   five grey stars read as a rating given; "When u need users to do an
   action needs to at least say it like Rate your experience"). A field's
   own label stays a noun (Name, Email): its box already asks.
12. **Retire it for good.** A word the user rejects joins
   `tests/words.js` (RETIRED, with the word to use) in the same push, so it
   can never return, and its rule joins this section; a kind of wording
   joins its PATTERNS, and a line said on two screens joins
   `ADspaceWords.line` and is read from there.
13. **A second reader.** The writer's own read is not the check: before
   merge the `/copy-review` skill hands the change's new words, with this
   section alone, to a reader who did not write them (CLAUDE.md §1).
