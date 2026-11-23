<!-- triggers: js/form.js -->
# Forms and dates

Moved from `CLAUDE.md` §2, One copy of each mechanism, on 2026-11-23. Each is the one copy of its mechanism: no page keeps its own.

- `js/form.js` owns forms.
  - Segments (`select[data-seg]`, the select stays the source of truth, out of
    the tab order; `ADspaceForm.thumb()` slides the surface; `.is-snap` on
    first placement and resize). One whose words do not fit equal columns
    first gives each option the room its words need (`is-auto`), then wraps;
    the words are measured with half a pixel of slack, never by a button's
    `scrollWidth`, which Chromium reports unclipped under an ellipsis
    (2026-10-29: Unavaila… read as fitting).
  - `details.fmore` (its line from `data-none`/`data-some`/`data-on`, a
    tick's off state from `data-off`; a field not on show, or inside
    `data-nosum`, stays off the line).
  - `reveal(el)` opens a fold before a refusal focuses into it.
  - The required asterisk comes from `aria-required` (`.is-req`).
  - The one save check (§10, the user, 2026-11-22: required fields saved
    empty): a sheet foot's primary, a form's submit or a `data-check-save`
    button is held while a field in its scope is required and empty (spaces
    alone too) or not of its kind (`type=number`, `email`, `tel`, `url`,
    `inputmode=url`, a date, `data-check` `amount` above 0, `whole`,
    `number`, `phone`, `url`; `min`, `max`, `step="1"`): the first wrong
    field focused, its fold opened, one `.check-note` under it (Enter the
    {label}. / Choose the {label}., 中文 on a 中文 page; `W.check*`).
    `ADspaceConfirm` asks it of every field; a page saving without a press
    asks `ADspaceForm.check(scope)`. `data-check-partial` (Billing's details
    before Active, a script's draft) holds only a wrong kind, as does
    `data-check-own` (a form naming its empty fields more fully: My Work's
    New names the post; Personnel's form its consent, then every
    field missing);
    `data-check-group` (a list's row) asks its required fields once one
    holds a value; `data-nocheck` is never held, and on a field never
    asked (its own rule in its own words: My namecard's Mobile). A form never types its own
    required check again; a client page's own checks state its database
    function's lengths and shapes beyond it.
  - `ADspaceForm.title` sets formal names in title case.
  - `ADspaceForm.named` / `sequence`: every client or colleague offered in a
    console select reads code first (`AC190 · Brand`, `AD014 · Xue Yi`), A to
    Z by code with digits as numbers, the unnumbered after by name
    (`byClient`, `byStaff`). The Clients list itself stays newest first.
  - The `data-hint` date hint.
  - A number of a known shape (`input[data-shape]`: # a digit, X a letter
    or digit, any other character laid in by itself) takes only what it
    holds as it is typed: an NRIC `######-##-####`, a BRN 12 digits, a
    passport 20 letters or digits; the creator's payment details and the
    supplier form alike, a kind changed clearing the number (the user,
    2026-11-09: "it says 12 digits but you never lock").
  - The date floor (below).
  - A long list is searched (§8): a select of ten options or more opens a
    finder (`#pickerBox`, `.picker`) in place of the browser's list, the
    field matching every word typed anywhere in an option's label (a name,
    a code, or part of either). The select stays the visible control and the
    source of truth: a pick sets its value and fires `input` and `change`; a
    value set from outside shuts the finder. A press, Space, Enter, the
    arrows or a key typed on the select opens it (the key typed is the first
    of the search; it reads Name or code, else the select's
    `data-find-hint`); Enter or a press picks, Escape, Tab and a press elsewhere
    shut it; Escape shuts it first wherever focus is, before a sheet under it. At a desk it hangs under the
    field; at 640 and under, or under a coarse pointer, it is a card above the tab bar of the
    screen's height named by the field's label, with a close mark, and a tap
    (not a scroll) opens it. Never on a `data-seg`, a multiple, a
    `.state-select`, a disabled select or `data-nofind`. Safari cannot run in
    the sandbox; the user confirms the iPhone tap.
- Dates (§5 of `js/form.js`): every date, month and date-time field is bounded
  to 14 Aug 2023 (ADSPACE PLT's registration) through 31 Dec 2099.
  - A lower `min` is raised.
  - A value out of range is cleared on blur and refused on Enter, with
    `.date-note`. `ADspaceAsk.rename` refuses it too.
  - `data-any-date` opts a field out. This is page-side only.
  - DD/MM/YYYY (§7): at a desk every `input[type=date]` becomes a text box
    (`.dmy`) showing DD/MM/YYYY, digits typed straight in taking their
    slashes and YYYY-MM-DD accepted; its calendar mark at the right edge (or
    the down arrow) opens the browser's picker through one hidden native
    field. Its `value` still reads and writes YYYY-MM-DD, so pages never
    change; the field's own min and max are held on blur ("Choose a date up
    to …"), and a part-typed date says "Enter the date as DD/MM/YYYY." A
    coarse pointer keeps the system's own box, as `data-native` keeps any
    one (My Work's pickers that open in place). Playwright's `inputValue()`
    reads the shown DD/MM/YYYY; the page's `value` is read in the page.
    The calendar is taken down after a day is picked, on a press elsewhere
    and on Escape (`shutPick()`: the hidden field's type cycled), because
    Safari left it over the page once the field it belonged to was gone.
    A picked day is read in the hidden field's `change` and everything
    else waits a tick (`setTimeout`): its type changed inside Safari's own
    change crashed the page, which Safari reloaded.
  - Room for the calendar (§6): at a desk, a date field too near the window's
    foot is lifted before its calendar opens (its scroller scrolls, else a
    `.pick-room` spacer), and a press that lifted it opens the calendar with
    `showPicker`. The spacer goes only as it leaves the view, never moving
    the screen under a press. A coarse pointer is left alone.
