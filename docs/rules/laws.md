<!-- triggers: css/ js/ admin/ client/ creators/ creator/ review/ script/ verify/ card/ quote/ details/ feedback/ supplier/ careers/ demo/ index.html 404.html docs/PAGE-TEMPLATE.html -->
# Laws (DESIGN.md §5: each broke once; the reasons are in the archive)

Moved whole from `DESIGN.md` §5, which keeps a one-line pointer here; read whole before building or changing a screen.


### Layout and alignment
- Two blocks in a section are always the same distance apart.
- A column is a column on every row. Every shared track is fixed and measured
  against its worst case (the clients state chip 120px; the Activity `By`
  150px; the task stage 170px; the schedule shoot 176px). `justify-self:
  stretch` aligns a cell and does not equalise the track.
- On a phone the last column is a right edge: the cell stretches and aligns
  right. An empty action cell gives up its track on a phone only.
- A phone list row is a two-column table, top aligned: who over meta on the
  left, state over age on the right, drawn by the phone row (`.prow`, §4). Two or three lines, never a stack of
  fields. Cells on one line share its baseline: a record beside an outlined
  chip reads on the chip's text (`.cr-record`). The right column's lines stand on
  the left's, line for line (the same line heights), never centred over a
  taller column (2026-11-04: a report's v1 sat above its brand name). A token that
  names the row (a Client ID) leads its meta line rather than taking a line
  of its own (2026-11-04: the Clients list read three lines against two).
- A phone template names every cell it keeps and hides the rest, including the
  restatement lower in the file.
- An empty grid cell keeps its column on a desk. `display:none` slides the rest
  left.
- A card's state chip sits on its title row at the right edge, before its ⋯
  (a record head, a month, a booking, a task's priority, a set, a post); the
  facts and the amount go on the lines under the name, on a phone as at a
  desk. In a desk table row a chip follows the name, never the far edge of
  a wide cell (a task's Urgent read as the assignee's).
- A value changed where it is read ends its mark on the facts' one right
  edge: the task card's date pens and detail chevrons alike (the user,
  2026-10-11: "the pen is here and there").
- A row holding a control keeps a row of words' height: the control's
  target overflows it evenly (a negative block margin), so facts stand one
  pitch apart whatever each row holds.
- A padded control on a card's last line gives its padding back with a
  negative block margin (the ⋯, the tick). A control whose
  presence depends on a permission never sizes its row.
- A chip, a ⋯ or a ring on a title line centres on that line, never on its
  own target: the control's cell takes the line's height and the 44px target
  overflows it evenly (the month card, a task row).
- A rule about something inside a pane keys on `is-narrow` / `is-tight`, never
  on a media query. The window is the measure only for a page's own head (the
  client portal).
- Every table states its own tracks. A template hung off `:not(...)` claims the
  wrong header.
- Every tab strip is the view strip: the tonal track, never a rule across the
  column, never bleeding past the page's margins. A report's step strip
  (`.rp-steps`, each step's summary under its name) is one too. A record's strip
  (`.rectabs`, the client portal's too) and a strip inside a card (a set's
  `.poststages`) run the width of that card at every width, as the Overview's
  strip of a client record does; a section's switch
  (`.tabrow`, or a view strip on its own row: My records, Performance, the Activity
  record) is its own width at a desk and the column's on a phone, up to a
  control sharing its line (`uxaudit` `strip`). Tabs in a full strip share what is spare
  (`flex: 1 0 auto`). It never wraps; it scrolls sideways with the edge that
  has more beyond it faded.
- The chosen tab always shows its word on the sliding thumb at 4.5:1: the
  thumb is painted in the page's own order, never promoted to a layer of
  its own (no `translate3d`, `translateZ` or `will-change` on a
  `.has-thumb::before`), since iOS Safari drew a promoted thumb over the
  word inside a phone sheet (2026-11-22; `tests/segkind.js`).
- A tab's count is a small pill (`.tab-n`, 12/600, radius 5): `--tonal`
  with the soft ink, red (`is-err`) only where what it counts needs acting
  on now (Content Review: Changes requested, on both sides; Overview: an
  item is late); a waiting or done count stays neutral (2026-10-07).
  It gives back its room on a phone (4px under 640, 3px under 400) before a
  tab's word is cut.
- On a phone a sideways swipe presses the tab beside the chosen one
  (`js/swipe.js`, a region's `data-swipe` naming its strip).
- A box that scrolls sideways is the containing block of what it holds (`position: relative`): a screen-reader label inside a board card escaped the board's scroll and widened the page by 986px (2026-10-27, the demo's columns).
- A component borrowed for its shape carries its old flex and behaviour. Use a
  class of its own (`.railrow`, never `.navitem`).
- A class name belongs to one component. A new component never reuses a name
  already styled elsewhere (grep `css/portal.css` and `css/console.css` first): Content Review's
  `.cr-rec` split the Creators List's record cell, then named `.cr-rec` too.
- An id is held once on a page, the console's one document included: a new
  view's ids take a prefix of their own, grepped in `admin/index.html` and
  the scripts first (2026-10-28: Overdue invoices' `#invCancel`, `#invMsg`
  and `#invView` were the campaign invoice form's; `tests/overdue.js`).
- A group that must stay together is one element in the markup, never a hope
  about where a wrap falls.
- A box a page redraws alone inside a stack of sections (/quote/'s `#qsExtraBox`) gives up its own box (`display: contents`), so each section in it keeps the stack's step and its hairline (2026-10-28).
- Text a person typed (a caption, a brief, a note, a place) breaks anywhere
  (`overflow-wrap: anywhere`), and a grid holding it states
  `minmax(0, 1fr)`, never an `auto` track: one unbroken link otherwise widens
  the card and the page. The walk seeds a 120-character link on both client
  pages. An address that is a row's meta line under its name is one line
  ending in an ellipsis; the whole address is one press away.
- Words never leave their box: a line is either whole inside its card or
  row, wrapping under itself and the row growing, or cut with an ellipsis;
  never cut bare at a column's edge or drawn over the next cell. A block
  inside a one-line cell (`.crm-c`) wraps (a client's name), since the
  cell's ellipsis never reaches it. `tests/fit.js` sweeps every console
  route from 1440 down to 900.
- An overlay is positioned against the box it explains (`.sched-field`), never
  its container.
- An image sized by one axis in a box that can clamp the other is squashed. The
  brand mark is `object-fit: contain; object-position: left center`.
- The bar and the foot run to the screen's edges on every page. Content keeps
  its reading width.
- The foot stands on the page's own ground (no band of its own), a `--line`
  rule above it; its bottom pad is the larger of 16px and the home bar's
  inset less 14px (20px on an iPhone, the tab bar's offset), never the two
  added; the © line stands above the home indicator. In a phone's browser
  (coarse pointer, `display-mode: browser`) the floor is 4px, about 19px
  above Safari's controls, which report no inset; Terms of Service keeps a
  44px press reaching upward.
- The last "not centred" is usually two type sizes. Measure the ink, the
  borders and the type before calling it even.

### Records
- The head is two parts centred on each other.
  - Left: the mark, the name and the meta.
  - Right: `.rec-ctl`, the state (chip or select, `align-self: center`) and one
    ⋯ holding Edit and Delete. Never Edit standing beside the name.
  - On a phone: `"mark . ctl" / "who who who"`.
- A form the team fills over time (a checklist, a paper form brought into
  the portal) is a record, never a page of open fields: it reads first,
  a tick is pressed in place, and each section's Edit opens its answers in
  a sheet (the user, 2026-10-15: "the checklist is coming back in the
  wrong design"). Before a screen ships it is checked against this file's
  components; a layout not in §4 is not invented.
- The landing pane is the record itself, built from what is loaded: flat
  sections with one control each; empty ones say so in a line.
- The rail is one block per question, ordered by need. A block with no data
  leaves. A written next action beats a derived one. A missing date's row is
  left out.
- A choice and an action never share a row unseparated: the choice carries
  its label at the left, the action sits at the right edge with its count
  just before it (the draft's language beside Write with AI).
- An act is offered once on a screen: a value is changed where it is read
  (its pen, its row's control), never again from a ⋯ (the user, 2026-10-09:
  Change sent date beside the Sent pen; Reassign beside Assigned to). What
  goes in a ⋯ is §5 Menus and action groups.
- A fact is stated once on a screen. A control that changes it answers
  (`Saved.`), and puts itself back on a refusal.
- A mark holds real artwork (`logo_url`, falling back to initials only while
  none is held). No monogram or avatar placeholders anywhere, no empty dashed
  discs.
- A completion figure is never the whole message: the bar carries its missing
  list.
- A page opens on what it is for, and everything that explains it folds. The
  fold's head carries the summary it is read for.
- A long list needs an axis (Group by) and a bound that never covers open work.
  Off the default axis every card is shut and the heading carries the count
  that matters.
- The commonest act on a row belongs on the row. A control inside a control is
  never nested: the name cell opens the record.
- A forward move is a button at its own width, never full width. Revert beside
  it is neutral, never a second blue. A client form's lone Submit (`.qs-foot`,
  /supplier/, /details/) stands at the column's right edge at a desk and full
  width on a phone; /quote/'s Back and Continue stay equal halves.
- The booking register clips its own rows (`.bookreg { overflow: hidden }`).
- A board is the same rows, one workflow at a time. Columns exist only where
  work can go. The drag reaches the same move as the select.
- A card on a board reads in order: what it is, whose it is, when it is owed.

### Forms, sheets, buttons
- Every add or edit form is a sheet over the list, never a panel unfolding at
  the top, never a form replacing the record's head.
- Buttons:
  - `.btn` is tonal (shaded, never outlined). The one outlined control is
    the contact chip `.plink`. A box typed into (`.input`, `.textarea`, a
    prefixed `.slugfield`, a code's boxes) is filled with `--field` and no
    outline, turning white with the blue edge and ring while typed in (the
    user, 2026-10-31, option B: "B"); every select (a status, a form's
    choice, a bar's view) is a tonal pop-up, the chevron at its end (the
    user, 2026-10-11). An invalid field keeps its red edge.
  - No bare text links in the portal: a way somewhere is a button, a chip
    or a `.btn-quiet` with a chevron (`.ovgo`), never an underlined word.
    Inside a line of facts it is `.linkbtn` (quiet, chevron, no underline);
    a typed address (a website, a profile, a past link) is a `.plink`.
  - The command bar's controls are 32px and take the small corner
    (`--radius-ctl-sm`).
  - Three roles, as Apple's (2026-10-07): `.btn-primary` and `.btn-go` are
    the one blue primary; `.btn` is tonal, caution included (`.btn-warn` is
    the tonal button, its question saying what it costs); `.btn-danger` is
    red words on the tonal button, never a red slab.
  - Every button that acts is shaded (the user, 2026-11-16: a word on a
    white card did not read as a button): `.btn-quiet` is the tonal ground
    like `.btn`, and words alone only as Cancel beside the view's blue
    primary (`:has(> .btn-primary, > .btn-go)`). A way inside a line of
    facts stays `.linkbtn`. A shaded button never gives its padding back
    sideways: its ground would stand past the words' edge (2026-11-20, a
    performance issue's Withdraw 13px left of its row, now its ⋯).
  - `.btn-sm`.
  - A sheet Cancel is `.btn-quiet`, never a bare `.btn` (`flex: 1` grows it).
    `.sheet-foot > .btn { flex: 0 0 auto }`.
- **Action rows read Cancel / secondary / Save from the left, anchored to the
  right edge** (`flex-direction: row-reverse`; the markup keeps the primary
  first).
  - Applies to `.sheet-foot`, `.row.acts`, `.changebox-actions`,
    `.zone-actions`, `.qform-acts`, `.filearm-acts`.
  - On a phone the two halves are equal, Cancel on the left; with three
    actions Cancel and the secondary are the halves and the primary takes
    the row under them, nearest the thumb: one rule for every sheet's foot
    at 640 and under (`css/console.css`), never a sheet's own copy
    (2026-10-20, DOC-1).
  - A count in the foot sits to the left of the pair (above it on a phone).
  - A sign-in reads Continue (blue) on the left and Use passkey (ink) on the
    right, as Apple's account pages do (the user, 2026-11-22); a cover's
    pair puts the way out (Sign out, Visit website) on the left.
- Controls in a row share a width and a height. `.row` aligns to the top, and
  `.row > .btn` to the bottom. Under a finger, at any width, two buttons or
  more sharing a row (`.kactions`, `.viewhead`, `.crm-engage-actions`) share
  one width: the phone's rules below 560, above it 220px each, the row
  wrapping rather than squeezing a label; a lone or quiet button keeps its
  own. A field standing alone fills its container.
- Controls made one height are brought down to the size token (`--ctl-h`, `--ctl-h-sm`), never raised to the tallest control a page holds; a page never sets `--ctl-h`, `--ctl-text` or `--field-text` to a figure of its own (2026-10-27: /quote/ was raised to 48, then read 16px words; `uxaudit` `ctlh`).
- A segment stores a value; a segment that only switches the view is a view strip: every `data-seg` select says which, `data-seg-value` or `data-strip` (`tests/segkind.js`, uxaudit `segkind`; 2026-11-22).
- A required field carries a red asterisk from `aria-required`.
- A typed box (`textarea`) runs its row's width and stretches downwards only
  (`resize: vertical`): a sideways drag never widens the page, and it grows
  with its words (`CLAUDE.md`, `js/grow.js`). A field that may outrun its
  width (a title, a link, a reason) is the one-line box: a field's height,
  its words wrapping onto a second line rather than hidden, no handle.
- A native field is reskinned to our box:
  - `::file-selector-button` shaded (`--line-soft`), concentric, 13px;
  - a date or time field with `appearance: none`, the value left aligned,
    `min-height: var(--ctl-h)`, and a glyph on the left under a coarse pointer;
  - at a desk a date box reads DD/MM/YYYY with the calendar mark at its right
    edge (`.dmy`, `js/form.js` §7); written dates stay `12 Sept 2026`;
  - the "Not set" hint on the field's wrapper.
- A control that creates a need answers it in place: the tick grows into the
  field (`.pbox`); the name grows out of Approve (`.namebox`). Both ends of a
  width animation are stated.
- One action is not a banner. A head's or bar's lone action keeps its own
  width; `:only-of-type` and `:has(.btn + .btn)` count `:not([hidden])` only.
- A field inside a growing box draws its focus ring inside itself
  (`.cmdbar-find .input:focus`).
- A value only read is not a field.
- Equal halves grow from a half's basis (`flex: 1 1 50%`), never from 0: a
  basis of 0 leaves each its own padding on top of its share (Request
  changes stood 34px wider than Approve; 2026-10-20).
- Delete has one place and one question (the user, 2026-10-10): the last
  item of the thing's own ⋯ (§5 Menus and action groups), red, never inside
  an Edit form and never a button on a row; it asks `ADspaceConfirm` (what goes, no restore), a
  record or anything holding other work with its name typed back, one item
  inside a record once, kept open on a refusal (`wait`). Remove is the soft
  way, asking nothing, with Undo where it happened. Several at once is the
  selection bar's red Delete with the count typed back (`tests/deletes.js`).
- A button that acts carries its action's glyph wherever it is drawn: a plus
  to add, a pen to edit, the copy mark, the file mark to download, the leaving
  mark after anything that opens in a new tab (Preview, Open), the chevron
  after a way to another console page. A form's own commit (Save, Cancel, a
  submit, a sheet's foot, a confirm) is words; a Preview in a sheet's foot
  is a way out, never its commit, and keeps its leaving mark. The act table is
  `js/acts.js` (Publish the plane, Unpublish the struck eye, Edit the pen,
  Download the file, Copy, Preview after the words, Add and New the plus, Invite, an email sent and Send code the envelope, Use passkey the key, Open in Bukku the leaving mark after, Open {a console page} and View the chevron after; a quiet button as a filled one):
  a button drawn as words alone takes its act's mark, so a new screen
  follows it untold. `uxaudit` `glyph` fails a label drawn both ways.
- A press is answered on the button (Doherty): while its write is out the
  button keeps its width and shows a turning ring in its own ink, after
  150ms so a quick answer never flickers (`js/acts.js`), then the outcome
  where it happened. The glyph is drawn in the button's own ink: a
  head's rule for its own mark never reaches a button inside it (`uxaudit`
  `glyphink`).
- A border inside a border groups nothing, so the inner one is shaded.
- A word or a value that acts inside a line of text (`.linkbtn`, `.tdate`,
  `.tinline`, `.serial-copy`) keeps its whole target but never shows it: its
  hover fill hugs the line (26px, a `::before`), never a slab the height of
  the target.
- A fact's value that opens its record (`dd > .linkbtn`: a client's
  supplier, a supplier's client) reads as the value: left aligned, in ink,
  wrapping as the facts beside it, the chevron after its last word, its
  target a control's height at any type size, given back to the line.
- A tonal toggle (`aria-pressed`, Review n changes) held on reads one step
  deeper (`--tonal-press`), its words in ink; never blue.
- Every button carries a base class (`.btn` and its variants, `.linkbtn`,
  `.kmenu-btn`): a class no rule styles draws the browser's own grey pill on
  an iPhone (2026-10-31: Show 1 removed quotation, `.linkish`). A list's
  removed rows open from a `.btn-quiet .btn-sm` (`.crm-removed-toggle`).
- The ⋯ is the lightest control. The account control, the bell and the
  search carry no outline, only a `--line-soft` fill on hover and while
  open.

### Menus and action groups
The user, 2026-10-22: "MENU standard: approve". Every ⋯ and every bulk bar
(`tests/menus.js`, uxaudit `menu`).
1. Screen or ⋯. An act goes on the screen when it is the record's next
   step, used on most visits, or its state is drawn beside it (a pen, a
   switch, a step button); in the ⋯ when it is rare, administrative or
   destructive. An item whose label matches a visible control on the same
   screen is not in the ⋯.
2. One ⋯ per thing: a record head's at its right edge after the state, a
   row's as its last cell. A ⋯ whose every item is withheld is not drawn.
3. Fixed order by group, a group with no item left out:
   1. Open: Open, Open file, Versions, Download (here even beside Preview
      PDF on screen).
   2. Change: Edit, Rename, Duplicate, New version, Take, Offer to
      team, Repeat, Reassign, Change reviewer, Transfer client, White label,
      Move up, Move down.
   3. Send: anything reaching a person outside the screen (Send on
      WhatsApp, Request feedback, Resend booking, Send
      invitation, Share with {name}).
   4. Mark: a flag reading its current value (Mark as VIC / Remove VIC,
      Mark restricted, Do not contact / Allow contact, Mark signed / Mark not signed, Confirm
      internally / Revert confirmation, Mark as not sent).
   5. Lifecycle: Set inactive / Set active, Archive / Restore, Pause /
      Resume, Cancel, Unpublish, Withdraw, Revert to …, Reopen,
      Stop, Cancel month, Reset link, Close link, Enable access / Revoke access
      (a contact), Allow portal sign-in / Stop portal sign-in (a Past client).
   6. Remove and destroy: Remove, Void, then Delete last.
   A website request not yet sent is the one exception (the user,
   2026-11-27): Download PDF, Show quotation link, Ask for details ·
   Edit, Cancel quote · Delete (`docs/rules/services.md`).
4. Separators (`hr.kmenu-sep`, `role="separator"`): always before group 6
   when anything precedes it; between the other groups once the menu
   shows four items or more.
5. Red only for group 6 (Remove, Void, Delete). Withdraw and Revoke in ink.
6. State gates the item: one that cannot apply in the record's stage or
   state is not drawn, never greyed, and its function refuses it too.
7. A toggle is one item naming its next state. Where the state and its way
   back are drawn on screen (a restricted account's rail block and Clear),
   the ⋯ offers only the way in.
8. At most seven items; more are split by moving the commonest act onto the
   screen, never by nesting. Never a ⋯ of one item beside another act (the
   user, 2026-11-17: "menu only sit one option, edit stays outside?"): an
   act standing beside a ⋯ that would hold one item joins it (a group's
   Edit beside its Delete, a request's Reply). A bar's ⋯ that would hold
   one item is that item's button instead (`.cmd-solo`, `.kmenu-solo`). A ⋯
   of one item stays only where it is a lifecycle or destroy act and
   nothing stands beside it. `tests/menus.js` holds it.
9. Words: verb first, one to three words, no object the context gives; the
   same act the same word everywhere (Reset link, Void, Issue
   document, Make primary, Duplicate, Cancel); never a mood (Mark not signed);
   the short word a familiar app uses, never a phrase where one word says
   it (Duplicate, never Make a copy; Cancel, never Not proceeding; Submit,
   never Submit for review; the user, 2026-10-31).
10. One look: every item 13.5px, weight 400, ink (a `<b>` inside carries no
    weight); one width at a desk (320px) and one on a phone; `role="menu"`
    and `role="menuitem"`; every item written by `ADspaceMenu.items(groups)`
    (`js/menu.js`, each item's group as `data-g`), or as static markup
    carrying `data-g`; `ADspaceMenu.tidy` lays the roles, the red and the
    separators whenever a menu shows.
11. On a phone every ⋯ hangs from its own button, a record head's too
    (under it, upward only where the room is above; it may cover the name
    while open), as an iPhone's pull-down menu does: the menu opens where
    the finger is (the user, 2026-10-24, reversing the foot dock of
    2026-10-22).
12. A bulk bar mirrors the row: only acts one row offers, in the same
    words; drawn once something is ticked and hidden (never greyed) at
    zero; Delete red and last.
13. Action groups on screen (`.rec-ctl`, `.kactions`, `.viewhead`, row
    acts): at most one blue; the state, the secondary, the primary at the
    right edge, the ⋯ last; on a phone buttons in a row share one width.
14. A sheet's foot is the form's commit: Cancel, an optional secondary, the
    primary, nothing else; list management (Add, Read from …, Select,
    Delete selected) goes in the sheet's own bar or its bulk bar.

### Colour, state, hover
- One status vocabulary and one colour set, on console and client pages alike
  (`W.TONE`, every status word with its tone). Pending and reviewing are
  amber.
- Late is red, waiting is amber (the user, 2026-10-07): what is past its
  date needs acting on today, so it takes the red dot or `--err`, the word
  beside it (Overdue, late, Urgent); what waits, or is still running, takes
  the amber dot. A count (`.tab-n`) is red only where it counts something to
  act on now; a waiting or done count is neutral.
- A stage select is toned by `stage_group`:
  - not started (and ready to start): grey;
  - in hand (in progress, a revision): amber, still running;
  - waiting on a person: amber;
  - cleared: green;
  - blocked: red.
- A lifecycle flag flipped once (Active / Inactive) is a chip plus a ⋯ item,
  never a select on every row.
- Hover is one step lighter than selected (`--sunk` against `--line-soft`),
  never equal. Every hover lives inside `@media (hover: hover)`. A hover is the
  next step of its ground, never `--fill`. Where the chosen is a white
  thumb or row on a grey ground (a strip's tabs, a segment, the rail on the
  frame), the hover is that white at half (`--card` at 55 to 60%), never a
  grey the ground already is (2026-11-13: the hover read as missing).
- The chosen one of several is a fill, never a shadow and never a weight:
  every tab, view, segment, nav item and finder option reads at 400, chosen
  or not (the user, 2026-10-04);
  - a nav item: `--line-soft`;
  - a tab, a view and a segment alike: one raised thumb that slides on the
    tonal track (`.rectabs`, `.tabrow`, `.cmdbar-views`, `.seg`);
  - a segment (a value picked) is a pill, track, options and thumb, its
    options 14px either side of the word; a tab or view strip (a screen
    moved to) keeps its corners. Round chooses, rectangular acts. A small
    select (`select-sm`) makes a small segment (`.seg.is-sm`): the small
    control's height and 12.5px type, options as wide as their words, the
    height of the small button it sits with. One whose words do not fit
    one line (four on a phone) is separate pills, two across and 8px
    apart, each tonal, the chosen the ink fill (`.seg.is-wrap`), and one
    still cut stacks (`is-stack`), never one block of four;
  - an `.acttab` outside a strip: the ink fill.
- A ticked row's fill must not cost a control its edge (an untinted select on
  a ticked row takes the mute ink edge).
- The iOS tap highlight is off (`-webkit-tap-highlight-color: transparent`).

### Responsive and phone
- Breakpoints:
  - 640 is the phone line (`.crm-head` hides; facts go two across);
  - 560 and 760 adjust some cards and sheets;
  - 1100 splits the record rail.
- `pointer: coarse` raises controls to 36px (32 small); a button's press stays 44px.
- Test at 1280 and 390; the matrix adds 320 to 1440 and 200% zoom.
- No horizontal overflow. A 16px side gutter. Never a sideways table (a
  board's columns are not a table).
- The head card ends above the fold. Nothing is clipped under the sticky bar.
  Sheets are measured in `dvh` (falling back to `vh`); on a phone each is a
  card risen from the floor to stand above the tab bar, never taller than
  the screen less the bar's room, and pads the safe area.
- A line of parts (`client · 10 creators · RM 8,640.00`) wraps between its
  parts, never inside one: a count and an amount hold their spaces.
- A chip on a name that clips stands beside the name, never inside its
  clipped box, and takes the line under it where both do not fit (an Ad
  error chip inside the name was cut away on a phone; 2026-10-20).
- A fact's span by its content (a fact holding chips takes the row)
  outranks its span by its place (the last of five takes two): a placing
  rule never wins on specificity alone (2026-10-21: On the day stood in two
  of three columns at a desk, a cell alone on its row).
- A narrow cell keeps its heading's meaning: a bare figure names itself when
  the header hides (`Over by | 4 days`).
- The phone command bar is one row plus the view segment.
- On a phone (and a touch screen narrower than a desk) the sections are the
  tab bar at the foot; everything that rises from the foot keeps
  `--tabbar-space` clear, and every panel is a card above the bar.
- On a phone the bell's panel takes the page gutters
  (`.kmenu.notif-menu`, fixed, 16px each side).
- The My Work view strip scrolls sideways with faded edges
  (`is-more-start`, `is-more-end`). Every view keeps its whole word.
- **Phone checklist, read on every screenshot:**
  - no cell alone on its row;
  - no value wrapping inside a cell;
  - buttons sharing a row share a width;
  - the primary is nearest the thumb;
  - a table row is two or three lines;
  - a lone field fills its container;
  - no pinned `style` width survives the phone line.
