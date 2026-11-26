<!-- triggers: css/ js/ admin/ client/ creators/ creator/ review/ script/ verify/ card/ quote/ details/ feedback/ supplier/ careers/ demo/ index.html 404.html docs/PAGE-TEMPLATE.html -->
# Directories and the command bar (CLAUDE.md §2)

Moved whole from `CLAUDE.md` §2, which keeps a one-line pointer here; read whole before building or changing a console list, its cards, filters, order, command bar, the rail's order or a route's purpose line.

- Every console directory is a card per group via `js/group.js`:
  - Clients by stage;
  - a client's Engagements by content month;
  - Content Review as one card; a client's sets by content month;
  - Creators as a tab a state (`#campStages`: Draft, Open for
    selection, In production, Completed, each counted, opening on the first
    that holds any), a card a month made (MYT) under it, newest open; a row
    reads Updated where the state would repeat its tab, and Booked n of N
    (creators booked of its slots, never the slots alone; 2026-10-22, CMP-8);
    on a phone the client and Booked n of N under the name, the amount under
    the date at the right edge (the user, 2026-11-14);
  - the Creators List by fee band (Inactive shut);
  - Short Links Live, Namecards, Paused (Paused shut);
  - Documents by family;
  - Services by category;
  - Team by user group;
  - the Handbook by category (Archived shut, `team.handbook` alone);
  - My Work by its axis.
- A filter never repeats the cards' own grouping: no state, kind, group or
  category filter on a route whose cards are those groups (Creators,
  Documents, Team, Services, Handbook, Short Links). An option for all reads
  All stages, All people, All months, never Every …, Everyone or Everything.
- A list puts what needs acting on first and what is finished last (2026-11-03,
  the user: "the more user friendly sequencing order"), the order otherwise
  kept: My Work's rows and board columns a VIC client's open work first, then
  priority and due date, finished work newest finished first (`rowOrder`);
  Leads past their follow-up time first; a client's quotations needing the
  team, then standing, then settled, then over (Expired, Revised,
  Cancelled); requests open first; service lines To quote, Confirmed,
  Enquired, each newest first; a void or replaced letter, a withdrawn
  notice, an inactive rate line, a cancelled month and a posted or completed
  booking after the rest; Content Review's sets in a month with changes
  requested first, then drafts, then published; a report month's rows on
  Published not sent first, then A to Z by the name they read; the client
  portal's meetings ahead first, soonest first, then held, latest first;
  Video Scripts' No month last. A history stays newest first and what waits
  on the reader oldest first.
- A filter repaints only when its value changed: `input` and `change` both fire,
  and `change` on blur detached Clear filters.
- A list reads what its rows show in one request (`.in()`, paged by the
  thousand), never one a row, and a repaint or a key typed reads nothing
  again: every request is a logged line Supabase meters (Content Review's
  read a client was a sixth of the live traffic, 2026-10-09; `tests/sets.js`).
- `.cmdbar-end` > `.cmdbar-quiet` (count) + `.cmdbar-acts` is one element, so a
  wrap cannot split it. An empty count is not drawn.
- The rail's order (see `DESIGN.md`) drives `SECTIONS`, the Activity record's
  sections (`ACT_SECTION`), `PARTS.activity`, and the Team panel's blocks. One
  sequence everywhere.
- The route's purpose line opens from the route name (`.console-title` button,
  14px glyph, `aria-expanded`; `.aboutpop` laid by `ADspaceMenu.pop(btn, pop, 'left')`).
  - One sentence per route, from `INTRO`.
  - Never opens by itself (the first-visit guide is the one that does). While
    a route is new, the glyph carries `--action`.
  - Below 400px the glyph gives way and the name never does.
- A standing fact about a route is a `.routenote` under the register:
  - the verify page as a link;
  - the redirect hosts `hi.adspace.me` and `go.adspace.me` as links.
