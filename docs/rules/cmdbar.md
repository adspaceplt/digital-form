<!-- triggers: js/state.js js/group.js js/cmdbar.js -->
# Loading states, directory cards and the command bar

Moved from `CLAUDE.md` §2, One copy of each mechanism, on 2026-11-23. Each is the one copy of its mechanism: no page keeps its own.

- `js/state.js` owns loading, empty and failed (`skeleton`, `emptyLine`,
  `failLine`) and `initials`. **A failed read is never drawn as an empty list.**
  - `fit` writes `is-narrow` (≤640) and `is-tight` (≤460) on `.console-body`,
    `.rec-pane` and `.rec-rail` from a `ResizeObserver`. A list may state its
    own line (`data-narrow="860"`) and its own tight line (`data-tight`: a
    booking register at 575, so a date and its time never cut), and a sheet outside the console body
    states one to be fitted at all (`#taskDrawer` `data-narrow="460"`).
  - Never container queries: they contain the fixed ⋯ menus.
- `js/group.js` draws every directory card:
  `ADspaceGroup.section({route, key, memo, name, count, marks, shut, table})`,
  `table()`, `more()`, `keep()`.
  - Thirty rows, then Show more; once pressed it keeps every row while the page
    is open.
  - Folds are remembered under `adspace-groups` (by route and key; `memo` per
    axis).
  - A filter opens every card.
  - A card holding everything never shuts by default.
- `js/cmdbar.js` owns the command bar.
  - Below 640: a search mark and a Filters mark (with a badge counting filters
    off their default), then the count and the primary as a filled `+`; a
    view segment it holds on a row of its own above them.
  - Tabs first, then the bar, on every section at every width (the user,
    2026-11-03: "why are some up and some below"): a section's strip (Clients,
    Creators and its stages, Reports, Services, Team) stands over its
    bar, 12px above the search, and every strip on its own row is the tab
    row's height; a desk keeps My Work's views at the left of the bar's own
    line (`tests/cmdbar.js`).
  - A record's pane heads itself one way (2026-11-03, the user: Calls and
    visits beside Quotations): each part an `h2` in `.viewhead` (15/600,
    the panel title's size, inside its card since 2026-11-13), its act a
    `.btn-sm` (quiet where it adds), and an empty list
    words alone, its act the heading's; `.empty` and `.emptyline` are one
    look and one height (the mute ink at 400; `tests/cmdbar.js`).
  - Every record leaves by one Back (`.backlink`: the arrow and the word
    Back) at one height, its section's own strip stepping away while it is
    open, and heads itself with `.rec-id` (the disc where the record holds
    a picture, a client's or a campaign's, else none: a supplier and a
    colleague head with the name, `.is-nomark`, 2026-11-04; the name over
    its meta, the state and the ⋯); Select is behind the bar's ⋯ in every section; an
    empty status line takes no room (2026-11-03, the user: "check all
    others too"; `tests/cmdbar.js`).
  - The bar's own selects are moved into `#cmdSheet` and back, never copied.
    Clear sets `data-default` (else the first option) and fires `change`.
    A field the page hides (`.cmdbar-find[hidden]`) takes its search mark with it.
    `data-nofilter` marks a select that is not a filter (`#workWf`,
    `#workScope`). `data-view` marks a view kept in the card (`#workGroup`,
    `#regSort`): never counted by the badge, never reset by Clear.
  - A bar's primary whose words a page writes later (Create n bills) writes
    them into its `.btn-word` and its name, never its `textContent`, which
    takes the phone's glyph away (2026-11-15).
  - A second action goes behind `.cmd-more` beside a primary; a bar of plain
    actions keeps its first and puts the rest there once it has three (the
    Performance Months bar); a button marked `data-rare` (with its `data-g`)
    is behind the ⋯ at every width, the ⋯ drawn at a desk for it alone and
    taking the focus back from what the item opens (Compare groups, Bulk
    import; SHELL-5, 2026-10-22); each item carries its button's
    `data-need` and follows its `hidden`, and the ⋯ leaves when nothing in it
    can be pressed. Its glyph is the row ⋯'s three dots across. A ⋯
    that would hold one item is not drawn: that item's own button stands
    on the bar (`.cmd-solo`; a section's own ⋯, My Work's and Reports',
    through `ADspaceMenu.solo`; the user, 2026-11-17).
  - Every filter is a pill (v3, 2026-11-12): at a desk on the bar's own
    line between the search and the count (the user, 2026-11-13: "we're
    wasting one row for the filters"), on a row of their own under it
    where the line cannot hold them, the count and the acts keeping the
    line (`fitPills`, measured as the bar or its search resizes), each filter whatever its value (`Stage: All stages`, its
    value in ink on the deeper tonal step once set), a press opening its
    choices as a menu under it (`.cmdpill-menu`, the arrows, Escape back to
    the pill); on a phone, on a row of their own under the bar, only the filters set, a press putting that one
    back (`.cmdbar-chips`, Label: Value with its ×). A view never a pill;
    Clear filters stays the card's and the empty list's
  - The Filters sheet focuses its card, never a select (a focused select wears
    the ring, and iOS does not open a select that already has focus).
  - A select the page shows or hides while the card or sheet is open is
    shown or hidden there at once (a `MutationObserver` on its `hidden`).
  - A Filters button over only hidden selects is not drawn.
  - At a desk every bar's search is a 32px mark that grows into a 280px field
    and shuts on Escape or when left empty.
  - At a desk the Filters mark (after the bar's last select) is drawn only
    for a select no pill holds (a view kept in the card: `#workGroup`,
    `#regSort`), its card hung from it (`#cmdPop`, `ADspaceMenu.pop`, Clear,
    Escape or a press elsewhere shuts it); a bar whose filters are all pills
    draws none (the user, 2026-11-13: a duplicate); a `data-nofilter` select
    is a view and stays in the bar at a desk.
