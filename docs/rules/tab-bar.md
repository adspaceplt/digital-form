# The phone tab bar and Arrange sections (`js/admin.js`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-22 and read before the area is changed. One place per fact, as CLAUDE.md §0.

- The phone tab bar (`#tabBar`, js/admin.js; the user, 2026-10-09): on a
  touch screen narrower than a desk (a foldable open or shut, a tablet
  upright) and on any window at 640 and under, the one media query
  `ADSPACE_TABBAR` (the head script, which sets `:root.has-tabbar` before
  first paint) puts the first four sections the person may open, in the
  rail's order, at the foot with More (`#tabMore`) opening the rest above
  it; five or fewer take the bar whole. More lists only what the bar does
  not (`.is-tabbed`), then the rail's foot: one line of the build at the
  left, then Settings' mark and the Activity record's at the right edge
  (each named for a screen reader and on hover); at a desk the rail is
  212px and its marks take a row of their own on the sections' left edge,
  the build under them (the user, 2026-11-13: "the left panel could width
  could be smaller") (the user, 2026-10-10: "activity log can go inline with version
  code", "just activity record icons would do"; 2026-10-11: "the settings
  button to fit beside activity record as just icons same as it", "the
  rearrange tabs also next to settings"), Arrange sections' mark first. The menu toggle gives way to it; the drawer stays for a narrow desk window.
  What pops up (a docked card, a ⋯ menu, More, the confirm bar) keeps above
  it through `--tabbar-space`; every panel (a sheet, a question, search,
  the task, the finder) is a card above it inside the gutters with the
  large corner, the bar in sight under its scrim and out of reach
  (`--sheet-floor`, `--sheet-top`; the user, 2026-10-11: "every panel
  opens a card above the bar on mobile"); a field taking the
  keyboard under a finger hides it (`is-typing`), never a select, date or
  time, which opens the system's picker (a card that moved under it jumped
  back under the finger; 2026-10-15). It floats (the user,
  2026-10-11, after Instagram's): a glass pill 10px above the home bar
  inside the gutters. The chosen tab is one fill (`.tabbar-thumb`) that
  slides to it and follows a finger dragged along the bar, letting go
  on a tab opening it ("allow the selected … button to slide around left
  right"); a section More holds chooses More. The Dashboard carries a red
  dot while Waiting for you holds anything (`ADspaceAdmin.waiting(n)`, from
  `paintWaiting`; read once on sign-in, the rail's Dashboard row counting
  it too; 2026-11-13), never a profile
  photo tab (`tests/tabbar.js`, `tests/waiting.js`). It sits low, 14px
  less than the home bar's inset above the edge (`--tabbar-bottom`; the
  user: "can go abit down"), and scrolling down draws it in to its glyphs
  (`.tabbar-min`: 54px, 56px a tab), scrolling up, the page's top, More or
  a press bringing the words back; the room the page keeps clear never
  changes. Where a phone's page stands upright and narrower than its
  screen (the iPhone Duo's front screen, Safari's controls in a column at
  its right; `ADSPACE_TABSIDE` in the head script, `:root.tabbar-side`,
  measured on the layout's width and never while pinched in),
  the bar stands upright at the right edge, its tabs glyphs alone named for
  a screen reader, the page keeping its column clear (`--tabbar-room`),
  More and every panel opening beside it, never drawn in, a finger drawn
  down it as along it (the user, 2026-10-27: "at the right as portrait
  tabs", "just the glyphs icons"; `tests/tabbar.js`). My Work held half a
  second opens My Work with Add task (`ADspaceOps.add`, My Work at Work;
  the user, 2026-10-11); a shorter press is a tap.
- Arrange sections (`2026-10-10-rail-order.sql`; the user, 2026-10-10:
  "mobile tab and web … both sync edits"): one order a colleague for the
  web rail and the phone tab bar alike. `#railEdit`, a mark at the rail's
  foot before Settings' (drawn with three sections or more; 2026-10-11, the
  user: "the rearrange tabs also next to settings") opens
  `#railSheet`: the rail's groups (Work, Internal) as lists, a section
  dragged by its grip or moved with the arrow keys on it within its group,
  the Dashboard fixed first; under the bar the rows it will hold read Tab
  bar; Reset order puts the standard back in the sheet; Save keeps it
  (`rail_order_set(p_sections)`, known keys once each, `bad-order`; empty
  is the standard). `rail_orders` has RLS on, no policy, no grant;
  `rail_order_mine()` is read once `me()` answers, a copy in this browser
  (`adspace-rail:{id}`) for the first paint. The page reorders the rail's
  own items (`applyRail`), so the bar, which takes the rail's first
  sections, follows. A section not named comes after in the standard
  order. The Activity record's Section select, the Team panel and search
  keep the standard order. Not filed in the Activity record.

## Components

Moved from DESIGN.md §4 on 2026-11-22.

| Need | Component |
|---|---|
| Moving between sections on a phone | `.tabbar` (`#tabBar`, `:root.has-tabbar`): a floating glass pill (`--tabbar-h` 60, sitting into the home bar's inset (14px less than it, 10px where there is none), inside the 16px gutters, `--line-lift` edge, `--shadow-lift`, the card at 86% over `saturate(180%) blur(20px)`, glass under a finger too) holding the first four sections the person may open and More, a glyph over a short word (`TAB_WORD`: Review, Campaigns, Links), 11px, `--ink-mute`; the chosen tab is one `--line-soft` thumb (`.tabbar-thumb`) that slides to it and follows a finger dragged along the bar, letting go on a tab opening it, its word in ink, never blue, never a weight; tabs share the width up to 120px each, centred beyond. The Dashboard carries the red dot (`.tabbar-dot`, `--dot-late`, named for a screen reader) while Waiting for you holds anything; My Work held down opens Add task. Scrolling down draws it in to its glyphs (54px high, 56px a tab, the words faded), as Instagram's does; scrolling up or the page's top brings them back. More opens the rail as an inset card above the bar (`--raised`, `--line-lift` edge, the large corner), holding only the sections the bar does not, then the rail's foot (the build at the left, Arrange sections', Settings' and the Activity record's marks at the right, 44px); every panel (a sheet, a question, search, the task, the finder) is a card above the bar the same way, inside the gutters with the large corner, the bar in sight under its scrim and out of reach; while the keyboard is up the bar steps away and the card takes its room. On the iPhone Duo's front screen (a page narrower than its screen) the pill stands upright at the right edge, 56px wide, 8px in, its foot on the usual floor, its tabs glyphs alone (52px each), the chosen fill sliding down it; the page keeps its column clear and More opens beside it |
