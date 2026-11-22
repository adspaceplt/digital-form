<!-- triggers: js/maintenance.js js/announce.js js/notice.js -->
# Page availability, the latest build, Announcements and Notices

Rules for this area, moved from CLAUDE.md §2 on 2026-11-22 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- The latest build (`2026-11-17-latest-build.sql`; the user, 2026-11-17:
  "ok build it", everyone on the same merged build): each minute the
  console's check runs (`often`'s `each`) it reads `/version.json` from
  Pages (no metered line); a build newer than the page's draws `#buildBar`
  (laid as `.upgradebar`: A new version is available., Refresh) and never
  refreshes by itself (review 2026-11-17: an unsaved commentary was lost to
  it). Settings, Portal:
  Require latest version (`team.upgrade`) stores the live build
  (`build_require(p_commit, p_built)`, `app_flags` `build:min`, `bad-build`
  for a build time ahead of now,
  filed `team.changed` under Portal from and to, Undo putting the one before
  back); `page_pulse` answers it to the console as `build`, its commit
  and time alone, never who set it, and a console below it, on screen,
  refreshes within the minute once idle, once for each build required
  (`adspace-build-for`; still below it after, it waits for Refresh now),
  its bar reading Refresh now. Idle: nothing open over the page (a sheet, question, menu, popover,
  finder, guide, bulk bar), no field holding the caret, no request out
  (`ADspaceAPI.loading.busy`), and no page's own `beforeunload` guard
  objecting (asked with a probe event). A refresh is Refresh app's, at most
  once in three minutes a tab; raw, nothing happens; client pages are
  untouched (`tests/buildsync.js`).
- Page availability (`js/maintenance.js`, `2026-10-29-page-availability.sql`;
  Upgrade mode a page at a time since 2026-10-29, the user: "Upgrade for
  /client page, Temporarily Unavailable for /admin, or selectively") is a
  cover, never a lock: the database keeps answering, but the quotation
  website covered makes nothing (`quote_website_create` `unavailable`).
  - A row of `app_flags` a page (`page:{key}`: admin, client, review,
    script, details, creators, creator, quote, supplier, verify, careers, and the system pages home, notfound, card; RLS on, no
    policy, no grant), its `kind` (`upgrade` Upgrade in progress, `paused`
    Temporarily unavailable), window, note, Chinese note and whether its
    cover offers Chat on WhatsApp. `page_states()` (anon) answers every page
    set, the console's notes (English and 中文) to the team alone; `page_set(p_pages, p_kind,
    p_note, p_note_zh, p_starts, p_ends, p_whatsapp)` (`team.upgrade`;
    `bad-page`, `bad-kind`, `bad-window`) sets several at once, filed
    `team.changed` under Portal ("Page availability: Client portal: Available
    → Temporarily unavailable · until … · note", Malaysia time);
    `page_states_all()` reads them for Settings. `maintenance_state` and
    `maintenance_set`, for a page served before, read and set every page.
  - Every portal page loads it (after `api.js`; `/` and the 404, which hold
    no database library, ask `page_states` by `fetch`), the system pages
    included (`home` the front door, `notfound` the 404 by its tag's
    `data-page`, `card` namecards; EVERY PAGE AVAILABLE, 2026-11-21, the
    user: "makes all pages up, including the main page"); a page reads its
    own row by its address. Short links (the Worker) are not a page. A
    client page covers itself under its own bar (`.maint-cover`, z-index 39;
    the rest `inert`): Upgrade in progress / 系统升级中 (`W.maintTitle`;
    `maintText` The portal will be available again shortly. / 系统将稍后恢复使用。;
    `maintBack` The portal will be available again by, then on its own line
    20 Nov 2026 (Friday), 12:30pm. / 系统将于以下时间前恢复使用：, then the date), or Temporarily unavailable / 暂时无法使用
    (`W.pausedTitle`, `pausedText`, Chat on WhatsApp where set), its note in
    the page's language, following the 中文 switch. A quotation link already
    sent (`/quote/?q=`) keeps opening while the website is only paused. Every
    open page, the console included, asks again every minute while on screen
    and on every return (`ADspaceMaintenance.often`), and at a set start or
    end: covered, it covers itself; uncovered, a covered page reloads (to its
    latest version). A read that fails (`ask(true)` answers null) changes
    nothing.
  - An open page's minute is one request (`page_pulse(p_audience, p_bell)`,
    `2026-10-09-one-check-a-minute.sql`, anon too): upgrade mode, the
    announcements and the bell, each as its own function answers it; a part
    joins with `often(key, take, alone, opts)`, and on a database without the
    function every part asks alone (every request is a line Supabase logs and
    meters; `tests/upgrade.js`, `tests/smsql.js` §9ze); to the console it
    also answers the build required (`build`).
  - The console's row covers it for anybody but an admin (the whole screen,
    with Sign out); an admin works on under `.upgradebar` (led by the amber
    dot, Console: Upgrade in progress until …, Turn off ending the
    console's alone). Settings, Portal: Page availability (`team.upgrade`,
    All pages available or n pages unavailable) opens `#pgSheet`: the pages
    by group (Team, Clients, Creators, Public with the Candidate page), then
    System pages (Front page, Page not found, Namecards) under their own
    heading, whose tick chooses the three while Select all never does; each one line at a desk (the
    name and its address, the state and when, the pen; on a phone the name
    over its address, the state over when, the pen beside), revamp D,
    2026-11-04; Select ticks several (a press on a row, or the tick for all), Set availability asking once for all. The
    question asks Availability (a segment), Starts, Ends (each a date beside
    its time, MYT; empty start is now, empty end waits, a time with no date
    is today's), a note, a 中文 note and Show Chat on WhatsApp (not the
    console's), saying under the choice what it does to that page, refusing
    in the sheet a window that does not end after its start and now; Undo
    puts each page back. It opens on Upgrading, never Available, unless the
    pages chosen share a set state (that state, their window kept where it
    is one; where their times or notes differ, the fields open empty over
    a mute line saying so, and each page keeps its own of every field left
    empty, only what is typed laid over all, `tests/upgrade.js`); Available lays the window and notes aside (the state chosen
    again brings them back), and a window typed under Available is refused
    (Choose Upgrading or Unavailable to set a start, an end or a note.; the user, 2026-11-20).
    Every date and time field is one height (`--ctl-h`, the small one
    `--ctl-h-sm`), never a floor, so a pair's labels share one line.
- Announcements (`js/announce.js`, `2026-10-07-announcements.sql`,
  `2026-10-07-announcements-several.sql`): one bar under the top bar, the
  team's on the console (laid like `.upgradebar`) and the clients' on every
  client page that loads `maintenance.js` (edge to edge under its bar)
  (`announcements`, RLS on, no policy, no grant). Several may be live for
  each audience (the user, 2026-10-07: "i want multiples for internal and
  also clients"): `announcement_now(audience)` answers every live one as a
  list (started or no start, its end ahead or none, not ended; Important
  first, then the newest, ten at most), the clients' to anyone and the
  team's to the team, never who wrote it; asked on load (the console once
  `me()` answers), every minute while on screen and on return. They share
  the one bar, never stacked: a slide each, with ‹ n/N › once there are two
  (the arrows and a swipe, round from the last to the first), the bar as
  tall as its longest line so moving along never moves the page. Info is
  the tonal ground, Important the same led by the amber dot; the words
  follow the page's language (中文 where given); an https link opens in a
  new tab; the reader's × hides the one on show in this browser
  (`adspace-ann-hide:{id}:{updated_at}`, so an edit returns it). Team:
  Announcements (`team.announce`, granted) on the Settings page opens the
  list (`#annSheet`: Team and Clients, each every line, live with Edit /
  Stop, which asks, stopped or ended with Restore (never asks, while its end
  is ahead) and Delete, and New): `announcement_save` (an ADspaceConfirm
  sheet: Tone, English, 中文 (a team's asks one Message: the console is
  English alone; the user, 2026-10-11), Link, Starts and Ends as a date
  beside its time, MYT; posting one adds it, never ending another),
  `announcement_end(id, on)` and `announcement_delete(id)` (asked first, no
  restore; refused `live` until stopped or ended; a row's own act is Edit,
  else Restore, its ⋯ Stop, or Delete last once stopped or ended); each filed `team.changed`
  under subject Announcements. A plain line, never a scrolling marquee. No
  bar is made while upgrade mode's cover is up (a box made after the cover
  would sit outside its `inert`).
- Notices (`js/notice.js`, `2026-10-09-team-notices.sql`; the user,
  2026-10-09: "send custom in-app notifications to all members, or to
  specific team member(s)"): Team: Notices (`team.notice`) on the Settings
  page opens the list (`#ntcSheet`: every notice sent, newest first, To,
  when, by whom, Read by n of N, Withdraw (asked: it leaves every bell; a
  push already on a phone stays) and Restore (never asks), and once
  withdrawn the row's ⋯ Delete (asked, no restore; `team_notice_delete`,
  refused `live` until withdrawn, the notice and every copy;
  `2026-10-10-notice-delete.sql`, run in the SQL Editor)) and New
  (`#ntcNewSheet`: Send to All colleagues / Selected colleagues, the
  colleagues ticked code first, Title (one line, 120) and Message (1,000),
  the count beside Send). `team_notice_send(p_title, p_body, p_to)` writes
  one `ops_notifications` row (kind `notice`, `notice_id`, `from_name`) to
  each active colleague but the sender (`bad-title`,
  `bad-body`, `no-one`; ten a sender in any hour, `too-many` with when the
  next can go, `2026-10-18-ten-notices-an-hour.sql`), so it reaches the bell
  and a push;
  `team_notices_list()` and `team_notice_withdraw(p_id, p_restore)`
  (`hidden_at` on every copy). `team_notices` has RLS on, no policy, no
  grant. Each is filed `team.changed` under subject Notices.
