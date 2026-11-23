<!-- triggers: js/guide.js -->
# The first-visit guide

Moved from `CLAUDE.md` §2, One copy of each mechanism, on 2026-11-23. Each is the one copy of its mechanism: no page keeps its own.

- `js/guide.js` (`ADspaceGuide.offer(key, guide)`, `open`, `leave`, `can`,
  `useServer`) is the only first-visit guide (the user, 2026-10-07: "a one
  time tutorial kind into the entire portal"):
  - A guide is up to three steps, each on a control the page draws (`at`):
    the first three drawn, so a step whose control is not drawn (a
    permission, an empty list, the other state of a screen) is left out, and
    a guide with none left waits for a visit that has one. `within` names
    the sheet a guide lives in (that sheet is not over the page; the card
    stands above it, `.is-insheet`, and Escape ends the guide before the
    sheet); `then` runs once it is finished or skipped, never on leaving.
  - `offer` opens it once, by itself, when nothing is drawn over the page
    (a sheet, a menu or popover card, a question, the review canvas, the
    finder, a cover, the console booting; drawn, not merely present: the
    Access denied cover sits in a hidden shell) and the section has finished
    drawing (no `.skel` on screen, the same steps on two reads); `open` is
    asked for.
  - A card (`.guidecard`, never `.kmenu`: the pages shut every menu on a
    press elsewhere), not a cover: laid by `ADspaceMenu.pop` from its step's
    control, which wears `.guide-on` (the focus ring, drawn inside a row,
    which its table clips); docked at the foot on a phone, its control
    brought to the middle of the screen, clear of the card; never over the
    command bar; nothing under it locked. Skip, then
    Next or Done; Escape (unless something is over it: that hears the key
    first), pressing the ringed control, opening something over it (a sheet,
    a menu, a post) or leaving the route ends it, and each counts it met. A
    scroll re-lays the card on its control and never pulls the page back.
  - Met is kept per person: a colleague's in `guide_seen`
    (`2026-10-07-first-visit-guides.sql`: `guides_seen()`,
    `guide_seen_mark(p_guide)`; RLS on, no policy, no grant), asked once
    `me()` answers, so a guide met at a desk is not met on a phone; a client
    page's in this browser (`adspace-guide:{key}`). The browser keeps a copy
    either way.
  - The console's guides are `GUIDES` in `js/admin.js`, a screen each
    (the user, 2026-10-10: "the entire portal of these sections"): a route,
    else a tab, a report's step or a sheet, as `guideKey()` reads the page
    (`settings`, `whatsapp.templates`, `whatsapp.compose`, `arrange`,
    `mine.health` before agreeing and `mine.checkin` after, `team.health`,
    `reports.entry`, `reports.text`, `reports.check`, `reports.review`;
    batch 2, 2026-11-21: `campaigns.record`, `campaigns.roster`,
    `campaigns.payments`, `whatsapp.email`, `overview.team`, and
    `analytics.tab` on any Analytics tab after the first), offered as the screen
    first appears (an address change, or the page settling after a sheet, a
    tab or a step is drawn); on a phone the tab bar's guide (`phone`: the
    sections, More, the name that arranges them) comes first, then the
    screen's. Show me around in the ⓘ card reopens the screen's own, else
    the section's, while a step of it is on screen; the client portal's, the review page's, the
    selection page's and the creator's page's are in their own scripts, in
    English and Chinese where the page has 中文 (it follows the switch).
  - The stand-in seeds every guide as met; `window.__guidesFresh` (or the
    tab's `adspace-guides-fresh`) starts a person on none (`tests/guides.js`).
