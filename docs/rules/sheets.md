<!-- triggers: js/menu.js js/sheet.js js/confirm.js js/ask.js js/grow.js -->
# Menus, sheets, questions and typed boxes

Moved from `CLAUDE.md` §2, One copy of each mechanism, on 2026-11-23. Each is the one copy of its mechanism: no page keeps its own.

- `js/menu.js` (`place`, `pop`, `onScroll`, `items`, `item`, `groupOf`,
  `tidy`) is the only copy of where a ⋯ or a popover card opens, and of
  what a ⋯ holds and in what order (DESIGN.md §5 Menus and action groups):
  every item carries its group (`data-g` 1 to 6; `groupOf(label)` is the
  one table of the standard's words, `item(a, label, need)` one item
  written from it), and `tidy` puts the items in group order, lays roles,
  separators and the red each time a menu shows; every ⋯ hangs from its
  button at every width, a record head's too (the user, 2026-10-24: the
  foot dock opened away from the finger). A new act's
  word joins `groupOf` and `tests/menus.js` together.
  - `pop(btn, card, align)` lays a popover card (`.popcard`: the bell's
    `#pushPop`, the section's `#sectionAbout`). It moves the card to body; at
    a desk it hangs from its control with a caret (`--caret`, `is-up`); under
    640 it docks at the foot of the screen inside the gutters and above the
    home bar (`is-dock`), rising from the floor.
  - Placed on the viewport; opens upward where the room is above.
  - Ignores the scroll that reveals its focused button (2px rule).
  - Follows its button on resize, and closes when the button leaves the page.
  - It is placed from where a fixed box beside it actually lands (a probe at
    0,0 in its own container), which covers a transformed sheet card and an
    iPhone after the date picker alike.
  - Stacking: `.kmenu` z-index 50, over the select bar (20) and the confirm bar
    (40), under sheets (55+).
  - An open ⋯ answers Escape before the sheet under it does, and hands focus
    back to its button.
- `js/sheet.js` is the only copy of how a form sheet opens and shuts.
  - Opens at its top: the sheet and `.sheet-body` are scrolled up and the card
    is focused with `preventScroll`. A `MutationObserver` does the same for any
    `.sheet` unhidden directly.
  - Focuses the card (`tabindex="-1"`, no ring), never a field (iOS zoom).
    Exception: a sheet whose whole purpose is one value.
  - After a failed save, focus goes to the first invalid field.
  - A line a sheet writes in its own `.msg` (`err`, `warn`) scrolls into
    view the moment it reads, one observer for every sheet; a form puts
    what its action waits for before what is optional (2026-11-24: Check in
    refused below a phone's screen read as a press that ran nothing;
    `tests/sheetline.js`).
  - The scrim closes only an untouched sheet. Escape and the close mark always
    close it. The close mark presses that sheet's own Cancel.
  - On a phone (≤640): a sheet is pulled down from its head (the grabber) to
    close, pressing its close mark (90px, or a flick); a form sheet (a foot
    with a filled action, fields) keeps a draft of the fields the person
    changed when it is left any way but its action (`sessionStorage`
    `adspace-draft:{sheet id}`, against the state it opened in, hidden
    fields included), restores it on the next open in that state with
    `.draftline` Draft restored · Discard, and so its scrim closes it even
    when touched. Pressing the action ends the draft. Files, passwords and
    `data-nodraft` fields are never kept. A desk keeps no drafts.
  - Focus is trapped, and handed back on close: to its opener where drawn,
    else to what held focus at the open (a `data-rare` button's ⋯; 2026-10-23).
  - `sheet(id, on, swap)` swaps two sheets in one frame (`.is-swap`).
  - Cmd/Ctrl + Enter presses, in order: the caret's small form, then the top
    form sheet's foot primary, then the pane form's primary.
    - Never a red, disabled or hidden button.
    - Never on a sheet with no foot.
    - Never while an input method is composing.
    - The primary carries `aria-keyshortcuts`.
  - A plain Enter presses the top sheet's foot primary too (the user,
    2026-10-11), from the card or a one-line field only: never from a
    search box (`type=search`, a combobox, `inputmode=search`,
    `data-noenter`), a box of lines, a button, a select, a segment or a
    switch, never inside a form that submits itself, never on the question
    sheet (it answers its own Enter) or with the finder open, never a red
    button. A sheet opened by `js/ops.js` holds its card, never its close
    mark (Enter there had shut the step sheet).
- `js/confirm.js` (`ADspaceConfirm.ask({title, body, go, tone, field|fields, match, cancel:false}, onYes)`)
  is every question with a consequence. **No `window.confirm`, `prompt` or
  `alert` anywhere.**
  - A field marked `half` sits beside the next one (a date and its time),
    `third` three across (a named section of three figures, `.is-third`);
    `head` opens a section with its heading (`.askhead`), and `note` is one
    mute line under the field (`.asknote`, its `aria-describedby`); a spec
    of `line` alone is one mute line the row's whole width (`.askrow`).
  - A field marked `tick` is a checkbox (`.tickline`, answering `on` or
    nothing, never required); a `choices` field marked `seg` is a segment.
    Focus lands on the first typed field, never a segment or a tick;
    `focus` names another, and under a finger it lands on the card.
  - A field asked for words (no `type`, no `rows`) is a one-line box
    (`data-oneline`); one whose `match` or seeded `value` is digits stays a
    field with the number keyboard. Enter answers from any field, never
    while an input method is composing (pinyin's Enter picks the word).
  - `check(values)` refuses in place what the fields cannot state alone (an
    end before its start): the sheet and what was typed stay.
  - `no` runs when the question is left unanswered (Cancel, the close
    mark, the scrim, Escape); a field marked `code` is an emailed code
    (the number keyboard, `one-time-code`).
  - A destructive question opens on Cancel; one that asks a name typed back
    opens on that field, where an empty Enter is refused.
  - `#askGo` and `#askCancel` are stable ids. `#askSheet` sits at z-index 95,
    above any sheet.
  - The way back (reinstate, set active, restore) never asks.
- `js/ask.js` asks for one value.
  - `rename(host, btn)` edits in place. The pen becomes the ink tick. Enter
    saves, Escape restores (before any sheet's Escape), an empty value keeps
    the field open, and blur neither saves nor discards. `type`/`value` are
    available for a date.
  - The field is the value itself: its own type and box height read from the
    value, one `.input.askfield` rule (tonal, no box line, no glyph, pulled
    back so the words keep their place; a date a date's width, `.is-date`).
    No screen sizes its own field. `tests/inplace.js` opens every one at a
    desk and under a finger.
  - `inline(btn)` grows the field out of the control.
  - `note(after)` is a textarea; `once` removes it with its answer, and the
    handle carries `box`.
  - `rename`'s `check(v)` refuses in place: the field stays open with what
    was typed and the refusal under it (`.askmsg`), as a sheet refuses
    (2026-10-20, TEAM-4); a number box holding what is no number is
    refused so (Enter a number.), never saved as nothing (2026-10-27,
    SVC-10).
  - There is no sheet in it.
- `js/grow.js` (`ADspaceGrow.fit(el)`) is the only way a typed box grows
  (the user, 2026-10-07: "Cell not increasing as i typed? Why still these
  issues again"): every textarea on a page that loads it (the console, the
  client portal, the selection page, the creator's page, the review page,
  `docs/PAGE-TEMPLATE.html`) fits its words as it is typed in, as it comes
  into view holding words, when a page sets its `value` (the setter is
  wrapped) and when the width changes, up to 60% of the screen, then
  scrolls; every scroller around it keeps its place while it is measured.
  `data-nogrow` keeps one still. No page grows its own (`tests/grow.js`).
  - Its handle only makes a box taller (the user, the same day: "couldnt be
    drag around like a toy"): never sideways, never below the words it holds
    (its `min-height` is the fitted height), never past 85% of the screen; a
    height dragged to is kept while typing (`data-floor`) and forgotten when
    the page sets new words.
  - A one-line field that may hold more than its width (a title, a link, a
    next action, a reason, a name typed back) is a textarea marked
    `data-oneline`: a field's height, its words wrapping onto more lines
    rather than sliding out of sight, no handle, never a line break (a
    pasted one becomes a space), Enter submitting its form as a field's
    would. `ADspaceAsk.rename` opens words in one; a date, a time, a number
    or a code stays an `input`.
- A sheet's refusal line comes into view (`js/sheet.js`): an observer is
  held on each open `.sheet` alone, from its unhiding (by `show()` or
  directly) until it is hidden, never on the whole document (review
  2026-11-24, `tests/sheetline.js`).
