<!-- triggers: client/ js/portal.js -->
# Client portal (`client/`, `js/portal.js`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- A contact prefers English or 中文 alone (`client_contacts_lang_check`; no
  Malay portal, the user, 2026-11-17). Until this browser presses the 中文
  switch, the portal opens in the signed-in contact's own language
  (`get_portal` `me.lang`) and the selection page in its client's primary
  contact's (`get_campaign` `lang`, `client_lang`), never stored as a choice;
  /review/ and /script/ are English alone (`tests/portal.js`, `tests/client.js`).
- It is one client at a time (a company select where one login holds access at
  several). The head is the console record's (`.rec-mark`, `.rec-who`,
  `.rec-ctl`): the mark, the name over the registered name, the state and
  Request change, which asks which change as a segment (Cancel service, never a bare
  Cancel beside the sheet's own; 2026-10-31; 2026-10-27,
  POR-1): Change of details, Upgrade,
  Downgrade or Cancel, the last three against a confirmed line (`#reqPick`);
  a line's ⋯ asks for that line alone.
- Under it one tab strip (`#cpTabs`, the view strip, `role="tablist"`, the
  arrows and Home/End move along it) and one pane at a time
  (`.cp-panes`, `data-swipe="cpTabs"`, `data-narrow="640"`). The pane rides in
  `?tab=` (Overview left out) and pushes history; a refresh lands on it. Every
  section is a white card (`.panel.cp-card`) with its title inside
  (`.cp-card-head`); a table inside a card is the card's rows.
  - Overview (the approved boards, 2026-11-25): on the left on the
    record's proportion, Rate your experience while asked, a tile a tab
    drawn (`#ovTiles`, `.cp-tile`: its glyph, its name, where it stands, one
    fact; the whole tile opens its tab; three across, two where four would
    leave one alone, two on a phone), Services (Confirmed and To quote as
    lines, open requests, each line of two months or more as a month a part
    of `.cx-track`), Engagements (Content Review over its latest month's
    sets, each campaign still running, each as it stands); on the right
    Your account manager (a person's round tile, the name over Account
    manager, WhatsApp and Email), Next meeting (a calendar leaf and the time
    in MYT, Join and Add to calendar, an .ics), Latest report (Download) and
    Company. One column at 900, read in the order rate, tiles, Services,
    Next meeting, Latest report, Engagements, account manager, Company. Each
    summary card's View all opens its tab.
  - A piece of work as it stands (`progRow`): its glyph tile, the name over
    its facts, the state at the right, a track of its parts
    (`ADspaceIcons.track`, the one segmented track, the selection page's
    standing too) and its words (`ADspaceIcons.legend`) on Open's line,
    unless a note (the next shoot) takes it. A content set's parts are its
    posts (Approved green; Changes requested and To review amber; the rest
    still to come), a campaign's its booked creators (`get_portal`
    `booked`, states alone, furthest along first), never who they are.
  - Every table row's name is led by its section's glyph tile
    (`.cx-tile.is-sm`): Services the grid, Requests the note, Letters the
    envelope, Reports the chart, Meetings the calendar, Feedback the star.
  - Services: confirmed and To quote lines (enquired never shown), with
    Upgrade / Downgrade / Cancel in a confirmed line's ⋯ and, for a line of
    two months or more, where its term is (Month n of N, ending); then Requests once
    one exists (Withdraw with Undo while Requested). A request sent opens
    this tab.
  - Invoices (2026-11-25, read from Bukku): a card in Services, after the
    lines and before Requests, never a tab of its own: a part of the
    client's work joins the tab it belongs to before the strip grows. Each
    invoice its number over its date, due date (until paid) and balance
    where part is paid, its amount, Paid, Outstanding or Overdue, and
    Download PDF (Bukku's own copy, a new tab); overdue first, then
    outstanding by due date, then paid, newest first. Read through
    `bukku-sync` `portal` as the signed-in contact: `portal_invoice_contacts`
    answers that client's Bukku contacts alone (as `month_invoice_contacts`
    reads them, a company billing another brand too left out) and refuses
    any other client as `get_portal` does; nothing is kept. Bukku not set
    up, or no linked contact, draws no card; any other failed read says so
    in it with Try again (`failCard`, the page's language), as a failed
    Feedback read does under the tab's name, never a hidden card
    (2026-11-25, review fixes S3; `tests/portalinvoices.js`, `tests/portalpastsql.js`).
  - Letters: Download redraws the snapshot.
  - Content Review's tab groups its sets by content month (`.cp-group-head`,
    the month and its count), newest first.
  - Content Review, Video Scripts and Creator Campaigns (one sign-in,
    `2026-11-08-client-portal-one-sign-in.sql`; the user, 2026-11-08,
    approving the portal's release 1): tabs after Overview, each drawn only
    once it holds something, read by `portal_work(p_client)` (the published
    sets with posts, approved, changes and waiting, the waiting count on
    the tab; the shared scripts) beside `get_portal`'s campaigns; each row
    its name over its month, its state, and Open, its page in this tab
    (`/review/?k=…#s-{set}`, `/script/?k=…#{id}`, `/creators/?k=…`). Opened
    by a signed-in contact of its client, the review and selection pages
    ask `portal_link_pass(p_kind, p_token)` (`ADspaceAPI.portalPass`): no
    access code is typed, the page decides as the contact
    (`ADspaceDecide.sign`: Deciding as {name}, no Change or Forget), Back
    returns to the portal's tab, and trigger `portal_decider_stamp` files a
    decision on `reviews` or `option_reviews` under the contact's own name
    whatever name was sent. A link opened with no sign-in, or by a
    colleague, asks its code as before.
  - Reports and Meetings: tabs drawn only once there is one; an address
    naming one before it is drawn opens it when it is. A meeting ahead with
    a link offers Join on its row, never in a ⋯ (2026-10-20, POR-2).
  - Account: Contacts read-only, Portal access (Person · Sign-in email),
    Payment only once `ADSPACE_ORG.bank` is set.
- A Past client's portal is shut (2026-11-24, the review's finding 3,
  `2026-11-24-past-clients-leave-the-portal.sql`): `portal_client_open` is
  the one answer (not inactive, and not Past unless kept on since its last
  move: `portal_kept_at` at or after `stage_since`), asked by
  `portal_clients()` and so by every portal function, by media-pass as the
  caller and by portal-login (`portal_login_name`); a contact of a shut
  client reads Access denied, answered exactly as a stranger. Enable access
  and Revoke access in a Past client's ⋯ (lifecycle, Clients: Contacts at
  Work) go through `client_portal_access_set` alone, filed `client.edited`
  (Client portal: off → on); a move back to Active opens it by itself and a
  later move to Past shuts it again, nothing written by the move
  (`tests/portalpastsql.js`, `tests/portalpast.js`).
- The portal never writes a record. A request is a row the team applies.
  Request change opens through `js/sheet.js` (focus held, Escape, focus back
  to the button, a press outside never closes it over typed text), and an
  unsent note comes back when it opens again until it is sent (audit F8,
  2026-10-10). Send keeps one key until the request is filed
  (`portal_request_once`, audit C1), so a reply lost on the way and a second
  press file one request; `portal_request` is the same with no key.
- A sign-in address is text, never a mailto pill.
- Covers: Client sign-in, Check your email, Access denied, Unable to load.
- The bar holds Sign out and 中文 alone: no bell, no notifications (the
  user, 2026-11-25).
- A contact reads its name with Primary contact at the right of the line, the
  role under it, then the reach chips; who signs in is said once, under
  Portal access. A past meeting is Completed (已完成), a future one Upcoming.
